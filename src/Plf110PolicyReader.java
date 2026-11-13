/* SPDX-License-Identifier: GPL-2.0-only */
import java.lang.reflect.Constructor;
import java.lang.reflect.Method;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

/* Read-only counterpart of ColorOS Settings' ScreenRefreshUtils.
 * Only getAppOverrideRefreshRateList is called; no settings/service setter.
 * DefaultRateList and RefreshRateList are separate, not live display FPS. */
public final class Plf110PolicyReader {
    static int rateAt(String vector, int position) {
        String[] parts = vector.split("-", -1);
        if (position < 0 || parts.length <= position) return -1;
        for (String part : parts) if (!part.matches("[0-9]{1,3}")) return -1;
        return Integer.parseInt(parts[position]);
    }

    private static void appendRecords(StringBuilder out, Object bundle,
            Method getter, String key, String kind, int position, Set<String> requested,
            Set<String> emitted)
            throws Exception {
        Object raw = getter.invoke(bundle, key);
        if (raw == null) return;
        if (!(raw instanceof ArrayList<?>)) throw new IllegalStateException("list type");
        for (Object entry : (ArrayList<?>) raw) {
            if (!(entry instanceof String)) continue;
            String record = (String) entry;
            int comma = record.indexOf(',');
            if (comma < 1) continue;
            String pkg = record.substring(0, comma);
            if (!pkg.matches("[A-Za-z0-9_][A-Za-z0-9_.]*")) continue;
            if (!requested.isEmpty() && !requested.contains(pkg)) continue;
            int rate = rateAt(record.substring(comma + 1), position);
            if (rate < 0) continue;
            out.append(kind).append('\t').append(pkg).append('\t').append(rate).append('\n');
            emitted.add(pkg);
        }
    }

    public static void main(String[] args) {
        try {
            if (args.length < 1 || !(args[0].equals("3") || args[0].equals("8")))
                throw new IllegalArgumentException("mode");
            int mode = Integer.parseInt(args[0]);
            Set<String> requested = new HashSet<String>();
            for (int i = 1; i < args.length; i++) {
                if (!args[i].matches("[A-Za-z0-9_][A-Za-z0-9_.]*"))
                    throw new IllegalArgumentException("package");
                requested.add(args[i]);
            }
            Class<?> type = Class.forName("com.oplus.screenmode.OplusDisplayModeManager");
            Constructor<?> constructor = type.getDeclaredConstructor();
            constructor.setAccessible(true);
            Object manager = constructor.newInstance();
            Object bundle = type.getDeclaredMethod("getAppOverrideRefreshRateList").invoke(manager);
            Class<?> bundleType = Class.forName("android.os.Bundle");
            if (bundle == null || !bundleType.isInstance(bundle))
                throw new IllegalStateException("bundle type");
            Method getList = bundleType.getMethod("getStringArrayList", String.class);
            StringBuilder result = new StringBuilder("INFO\tpolicy_backend=vendor\nINFO\tpolicy_mode=");
            result.append(mode).append('\n');
            int position = mode > 3 ? 4 : 3;
            Set<String> defaults = new HashSet<String>();
            appendRecords(result, bundle, getList, "DefaultRateList", "DEFAULT", position, requested, defaults);
            appendRecords(result, bundle, getList, "RefreshRateList", "SYSTEM_OVERRIDE", position, requested, new HashSet<String>());
            Set<String> followApp = new HashSet<String>();
            Object notSupported = getList.invoke(bundle, "NotSupportOverrideList");
            if (notSupported instanceof ArrayList<?>) {
                for (Object value : (ArrayList<?>) notSupported) {
                    if (value instanceof String) followApp.add((String)value);
                }
            }
            for (String pkg : requested) {
                if (followApp.contains(pkg)) result.append("FOLLOW_APP\t").append(pkg).append("\t0\n");
                else if (!defaults.contains(pkg)) {
                    // Verified Settings preload fallback for an unlisted package.
                    result.append("DEFAULT_FALLBACK\t").append(pkg).append("\t1\n");
                }
            }
            System.out.print(result.toString());
        } catch (Throwable error) {
            System.err.println("policy reader unavailable: " + error.getClass().getSimpleName());
            System.exit(1);
        }
    }
}
