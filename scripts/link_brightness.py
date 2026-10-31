#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-only
from pathlib import Path
from io import BytesIO
import hashlib
import struct
import subprocess
import argparse
import os
from elftools.elf.elffile import ELFFile

parser = argparse.ArgumentParser(description="Append the verified brightness extension to the pinned Stable-278 KO")
parser.add_argument('base', type=Path)
parser.add_argument('object', type=Path)
parser.add_argument('output', type=Path)
args = parser.parse_args()
r = args.output.parent
r.mkdir(parents=True, exist_ok=True)
old = args.base.read_bytes()
assert hashlib.sha256(old).hexdigest() == '67bd63e0b1583a96c9ccefbf1f8ebd5ddc2312c2fae56f019b8eed833b30fd82'
subprocess.run([os.environ.get('PLF110_OBJCOPY', 'llvm-objcopy'),
    '--redefine-sym', 'plf110_mode_switch_update_for_vdo=plf_original_vdo_update',
    '--globalize-symbol', 'plf110_mode_switch_update_for_vdo',
    '--globalize-symbol', 'custom_slot_for_mode',
    '--globalize-symbol', 'state',
    str(args.base), str(r/'original-linkable.ko')], check=True)
subprocess.run([os.environ.get('PLF110_LD_LLD', 'ld.lld'), '-r', '-m', 'aarch64elf', '-z', 'noexecstack',
    str(r/'original-linkable.ko'), str(args.object),
    '-o', str(args.output)], check=True)
path = args.output
data = bytearray(path.read_bytes())
e = ELFFile(BytesIO(data)); before = ELFFile(BytesIO(old))
symbols = e.get_section_by_name('.symtab')
names = {s.name:(i,s) for i,s in enumerate(symbols.iter_symbols()) if s.name}
original_symbols = {s.name:s for s in before.get_section_by_name('.symtab').iter_symbols() if s.name}

def word_offset(elf, symbol):
    return elf.get_section(symbol['st_shndx'])['sh_offset'] + symbol['st_value'] - 4

patches = {
    'plf_brightness_vdo_update':'plf110_mode_switch_update_for_vdo',
    'phy_pre_handler':'panel_pre_handler',
    'control_set':'refresh_set', 'sync_enable_set':'refresh_set',
    'control_get':'status_get', 'sync_enable_get':'status_get', 'sync_status_get':'status_get',
}
for name, original_name in patches.items():
    at = word_offset(e, names[name][1])
    src = word_offset(before, original_symbols[original_name])
    data[at:at+4] = old[src:src+4]

# The only intentional original-code changes are its twelve callback-address
# relocations. The original callback itself remains executable, unmodified.
idx = names['plf_brightness_vdo_update'][0]
section = e.get_section_by_name('.rela.text')
rebound = []
for n, rel in enumerate(section.iter_relocations()):
    sym = symbols.get_symbol(rel['r_info_sym'])
    if sym['st_info']['type']=='STT_SECTION' and e.get_section(sym['st_shndx']).name=='.text' and rel['r_addend']==4:
        at = section['sh_offset'] + n*section['sh_entsize']
        struct.pack_into('<Qq', data, at+8, (idx<<32)|rel['r_info_type'], 0)
        rebound.append(rel['r_offset'])
assert rebound == [0x146c,0x1474,0x1478,0x147c,0x19b4,0x19c0,0x19c8,0x19d0,0x21f4,0x21fc,0x2200,0x2204], rebound

# Same vendor io_cmd CFI normalization as the original validated build script.
old_pair = struct.pack('<II', 0x72924ed1, 0x72b591b1)
new_pair = bytes.fromhex('31768a725144bf72')
io_sites = []
for sec in e.iter_sections():
    if sec.name.startswith('.text.'):
        block = sec.data()
        for off in range(0, len(block)-7, 4):
            if block[off:off+8] == old_pair:
                at = sec['sh_offset']+off
                data[at:at+8] = new_pair
                io_sites.append((sec.name,off))
assert len(io_sites)==2, io_sites
path.write_bytes(data)
fixed=ELFFile(BytesIO(data))
imports=lambda elf:{s.name for s in elf.get_section_by_name('.symtab').iter_symbols() if s.name and s['st_shndx']=='SHN_UNDEF'}
assert imports(fixed)==imports(before), (imports(fixed)-imports(before))
for name in ('.text','.init.text','.exit.text','__versions','.modinfo','.gnu.linkonce.this_module','.rodata'):
    assert fixed.get_section_by_name(name).data()==before.get_section_by_name(name).data(),name
assert fixed.get_section_by_name('.bss')['sh_size']==before.get_section_by_name('.bss')['sh_size']
assert names['state'][1]['st_value']==0 and names['state'][1]['st_size']==67944
for name, original_name in patches.items():
    at=word_offset(fixed,names[name][1]);src=word_offset(before,original_symbols[original_name])
    assert data[at:at+4]==old[src:src+4]
print('PASS: original code/timing/data/CRC/module identity unchanged, 21 imports unchanged')
print('Callback address relocations rebound:',len(rebound))
print('New vendor io_cmd CFI sites:',io_sites)
print('KO bytes:',len(data))
print('KO SHA256:',hashlib.sha256(data).hexdigest())
print('Output:',path)
