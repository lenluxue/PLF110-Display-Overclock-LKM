// SPDX-License-Identifier: GPL-2.0-only
#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/file.h>
#include <time.h>
#include <unistd.h>
#include "brightness_gain.h"

#ifndef SYSROOT
#define SYSROOT "/sys"
#endif
static const char *status_path=SYSROOT "/module/PLF110_Display_OC/parameters/status";
static const char *request_path=SYSROOT "/class/leds/lcd-backlight/brightness";
static const char *panel_path=SYSROOT "/kernel/oplus_display/oplus_brightness";
static const char *hbm_path=SYSROOT "/kernel/oplus_display/hbm";
static const char *fingerprint_path=SYSROOT "/kernel/oplus_display/dimlayer_hbm";
static const char *alpha_path=SYSROOT "/kernel/oplus_display/dim_alpha";
static const char *sync_status_path=SYSROOT "/module/PLF110_Display_OC/parameters/brightness_sync_status";
static const char *sync_control_path=SYSROOT "/module/PLF110_Display_OC/parameters/brightness_sync_control";
static const char *sync_enable_path=SYSROOT "/module/PLF110_Display_OC/parameters/brightness_sync_enable";
static bool sync_allowed=false;
static long sync_seen=0,sync_gain=-1,sync_request=-1,sync_guard=-1;
static double next_sync_probe=0;
static double now(void);
static volatile sig_atomic_t stopping=0;
static bool owned=false;
static long last_written=-1;
static const char *moddir=NULL;
struct snapshot {long rate,hopping,installed,request,panel;};
static void signal_stop(int signal_number) {(void)signal_number; stopping=1;}
static long number(const char *text) {
    char *end=NULL;
    errno=0; long v=strtol(text,&end,10);
    if(errno||end==text) return -1;
    while(*end==' '||*end=='\t'||*end=='\r'||*end=='\n') end++;
    return *end ? -1 : v;
}
static long gain_number(const char *text) {
    unsigned int units;
    while(*text==' '||*text=='\t'||*text=='\r'||*text=='\n') text++;
    if(plf_parse_gain(&text,&units)) return -1;
    while(*text==' '||*text=='\t'||*text=='\r'||*text=='\n') text++;
    return *text ? -1 : (long)units;
}
static void gain_text(char *text,size_t cap,long units) {
    if(units%PLF_GAIN_SCALE)
        snprintf(text,cap,"%ld.%ld",units/PLF_GAIN_SCALE,units%PLF_GAIN_SCALE);
    else snprintf(text,cap,"%ld",units/PLF_GAIN_SCALE);
}
static int text_file(const char *path,char *buf,size_t cap) {
    int fd=open(path,O_RDONLY|O_CLOEXEC);
    if(fd<0) return -1;
    ssize_t n=read(fd,buf,cap-1);
    int err=errno; close(fd); errno=err;
    if(n<=0) return -1;
    buf[n]=0; return 0;
}
static long read_number(const char *path) {
    char b[64]; return text_file(path,b,sizeof(b)) ? -1 : number(b);
}
static long read_gain(const char *path) {
    char b[64]; return text_file(path,b,sizeof(b)) ? -1 : gain_number(b);
}
static long token(const char *text,const char *key) {
    size_t len=strlen(key);
    for(const char *p=text;*p;) {
        while(*p==' '||*p=='\n') p++;
        const char *end=p;
        while(*end&&*end!=' '&&*end!='\n') end++;
        if((size_t)(end-p)>len&&!memcmp(p,key,len)&&p[len]=='=') {
            char b[64]; size_t n=(size_t)(end-p)-len-1;
            if(n>=sizeof(b)) return -1;
            memcpy(b,p+len+1,n); b[n]=0; return number(b);
        }
        p=end;
    }
    return -1;
}
static bool read_mode(struct snapshot *s) {
    char b[2048];
    if(text_file(status_path,b,sizeof(b))) return false;
    s->rate=token(b,"data_rate"); s->hopping=token(b,"hopping");
    s->installed=token(b,"installed");
    return s->installed==1&&s->rate>0&&(s->hopping==0||s->hopping==1);
}
static bool same_mode(const struct snapshot *a,const struct snapshot *b) {
    return a->installed==b->installed&&a->rate==b->rate&&a->hopping==b->hopping;
}
static bool sample(struct snapshot *s) {
    if(!read_mode(s)) return false;
    s->request=read_number(request_path); s->panel=read_number(panel_path);
    return s->request>=0&&s->request<=4095&&s->panel>=0&&s->panel<=4095;
}
static bool same(const struct snapshot *a,const struct snapshot *b) {
    return same_mode(a,b)&&a->request==b->request&&a->panel==b->panel;
}
static bool protected_brightness(void) {
    // Missing protection interfaces make the worker read-only.
    return read_number(hbm_path)!=0||read_number(fingerprint_path)!=0||
           read_number(alpha_path)!=0;
}
static long corrected(long request,long gain) {
    if(request<=1||request>3515) return request;
    return plf_gain_target((unsigned int)request,(unsigned int)gain);
}
static bool write_panel(long value) {
    char b[32]; int length=snprintf(b,sizeof(b),"%ld\n",value);
    int fd=open(panel_path,O_WRONLY|O_CLOEXEC);
    if(fd<0) return false;
    ssize_t n=write(fd,b,(size_t)length);
    int err=errno; close(fd); errno=err;
    return n==length;
}
static bool module_disabled(void) {
    if(!moddir) return false;
    if(access(moddir,F_OK)!=0) return true;
    char p[1024];
    for(unsigned i=0;i<2;i++) {
        int n=snprintf(p,sizeof(p),"%s/%s",moddir,i ? "remove" : "disable");
        if(n<0||(size_t)n>=sizeof(p)||access(p,F_OK)==0) return true;
    }
    return false;
}
static void relinquish(void) {owned=false;last_written=-1;}
static void restore_owned(void) {
    if(!owned) return;
    struct snapshot s,verify;
    if(!sample(&s)||s.panel!=last_written) {relinquish();return;}
    if(s.request==s.panel) {relinquish();return;}
    if(s.request<=1||protected_brightness()) return;
    if(!sample(&verify)||!same(&s,&verify)) return;
    if(write_panel(s.request)) {
        printf("restore DBV=%ld\n",s.request); relinquish();
    }
}
static bool write_text(const char *path,const char *text) {
    int fd=open(path,O_WRONLY|O_CLOEXEC);
    if(fd<0) return false;
    size_t length=strlen(text);ssize_t n=write(fd,text,length);
    close(fd);return n==(ssize_t)length;
}
static void adopt_kernel_output(const char *status,const struct snapshot *s) {
    long queued=token(status,"queued");
    if(queued>0&&queued!=sync_seen&&token(status,"request")==s->request&&
       token(status,"target")==s->panel) {
        if(s->panel!=s->request) {owned=true;last_written=s->panel;}
        sync_seen=queued;
    }
}
static void update_kernel_sync(long gain) {
    char status[512],text[64];struct snapshot s;
    if(now()<next_sync_probe) return;
    if(text_file(sync_status_path,status,sizeof(status))) {
        next_sync_probe=now()+5;return;
    }
    long enabled=token(status,"enabled");
    bool valid=sample(&s);
    if(valid) adopt_kernel_output(status,&s);
    if(!sync_allowed) {
        if(enabled==1) write_text(sync_enable_path,"0\n");
        return;
    }
    // Do not feed fractional percentages to an older integer-only KO.
    // Its existing output ownership is adopted above before safe fallback.
    if(gain%PLF_GAIN_SCALE&&token(status,"gain_scale")!=(long)PLF_GAIN_SCALE) {
        if(enabled==1) {
            write_text(sync_control_path,"100:0:1\n");
            write_text(sync_enable_path,"0\n");
        }
        next_sync_probe=now()+5;
        return;
    }
    if(!valid) return;
    long guard=protected_brightness()||
        (s.panel!=s.request&&!(owned&&s.panel==last_written)) ? 1 : 0;
    if(gain!=sync_gain||s.request!=sync_request||guard!=sync_guard) {
        char percent[16];gain_text(percent,sizeof(percent),gain);
        snprintf(text,sizeof(text),"%s:%ld:%ld\n",percent,s.request,guard);
        if(!write_text(sync_control_path,text)) {next_sync_probe=now()+5;return;}
        sync_gain=gain;sync_request=s.request;sync_guard=guard;
    }
    if(enabled==0) {
        if(write_text(sync_enable_path,"1\n")) puts("kernel brightness sync enabled after boot");
        else {puts("kernel brightness sync unavailable; userspace fallback");next_sync_probe=now()+5;}
    }
}
static void stop_kernel_sync(void) {
    char status[512];struct snapshot s;
    if(!text_file(sync_status_path,status,sizeof(status))&&token(status,"enabled")==1) {
        if(sample(&s)) adopt_kernel_output(status,&s);
        write_text(sync_control_path,"100:0:1\n");
        write_text(sync_enable_path,"0\n");
    }
}
static void step(long gain) {
    struct snapshot s,verify;
    if(!sample(&s)) return;
    if(owned&&s.panel!=last_written) relinquish();
    bool custom=(s.hopping==1&&s.rate==1399);
    bool normal=(s.request>=2&&s.request<=3515);
    long target=custom&&normal ? corrected(s.request,gain) : s.request;
    if(s.panel==target) {
        if(target==s.request) relinquish();
        return;
    }
    // Only replace an unmodified OEM request or an output this worker owns.
    if(s.panel!=s.request&&!(owned&&s.panel==last_written)) return;
    if(s.request<=1||protected_brightness()) return;
    if(!sample(&verify)||!same(&s,&verify)) return;
    if(!write_panel(target)) {
        fprintf(stderr,"brightness write failed: %s\n",strerror(errno));
        stopping=1; return;
    }
    char percent[16];gain_text(percent,sizeof(percent),gain);
    printf("%s request=%ld output=%ld gain=%s%%\n",custom ? "144" : "stock",s.request,target,percent);
    if(target==s.request) relinquish();
    else {owned=true;last_written=target;}
}
static double now(void) {
    struct timespec t;
    if(clock_gettime(CLOCK_MONOTONIC,&t)) exit(7);
    return (double)t.tv_sec+(double)t.tv_nsec/1e9;
}
static void pause_for(unsigned milliseconds) {
    struct timespec t={milliseconds/1000,(milliseconds%1000)*1000000L};
    while(nanosleep(&t,&t)&&errno==EINTR&&!stopping) {}
}
static void pause_100ms(void) {pause_for(100);}
#ifndef UNIT_TEST
int main(int argc,char **argv) {
    if(argc!=4&&argc!=5) {
        fprintf(stderr,"usage: %s GAIN(70..100, step=0.1) SECONDS(1..300 or 0=daemon) CONFIG [MODDIR]\n",argv[0]);
        return 2;
    }
    long gain=gain_number(argv[1]),seconds=number(argv[2]);
    if(gain<PLF_GAIN_MIN||gain>PLF_GAIN_MAX||seconds<0||seconds>300) return 2;
    if(argc==5) moddir=argv[4];
    int lock_fd=-1;
    if(moddir) {
        char lockpath[1024];
        int n=snprintf(lockpath,sizeof(lockpath),"%s/.brightness_comp.lock",moddir);
        if(n<0||(size_t)n>=sizeof(lockpath)) return 2;
        lock_fd=open(lockpath,O_CREAT|O_RDWR|O_CLOEXEC,0600);
        if(lock_fd<0) {perror("worker lock");return 3;}
        if(flock(lock_fd,LOCK_EX|LOCK_NB)) {
            int lock_error=errno;
            close(lock_fd);
            return lock_error==EWOULDBLOCK ? 0 : 3;
        }
    }
    setvbuf(stdout,NULL,_IONBF,0);
    struct sigaction sa={0}; sa.sa_handler=signal_stop;
    sigaction(SIGTERM,&sa,NULL);sigaction(SIGINT,&sa,NULL);
    double started=now(),last_config=started-2.0,last_disabled=started-0.1;
    char percent[16];gain_text(percent,sizeof(percent),gain);
    printf("brightness compensation start gain=%s%% duration=%lds\n",percent,seconds);
    while(!stopping&&(!seconds||now()-started<seconds)) {
        double t=now();
        if(t-last_disabled>=0.1) {
            if(module_disabled()) break;
            last_disabled=t;
        }
        if(t-last_config>=1.0) {
            long next=read_gain(argv[3]);
            // A deleted/invalid config disables compensation and restores.
            gain=(next>=PLF_GAIN_MIN&&next<=PLF_GAIN_MAX) ? next : PLF_GAIN_MAX;
            char config[1024];
            if(moddir&&snprintf(config,sizeof(config),"%s/brightness_sync.conf",moddir)<(int)sizeof(config))
                sync_allowed=read_number(config)==1;
            else sync_allowed=false;
            last_config=t;
        }
        // The kernel queues the transition compensation. This 20ms worker
        // maintains original LED requests and a userspace fallback only.
        update_kernel_sync(gain);step(gain);
        pause_for(20);
    }
    stop_kernel_sync();
    restore_owned();
    // Allow a brief fingerprint transaction to finish before restoring.
    for(unsigned i=0;owned&&i<20;i++) {pause_100ms();restore_owned();}
    puts("brightness compensation stopped");
    if(lock_fd>=0) close(lock_fd);
    return owned ? 6 : 0;
}
#endif
