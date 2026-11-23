import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:flutter/services.dart';

const bg = Color(0xFF090D13);
const panel = Color(0xFF151C26);
const panel2 = Color(0xFF202A36);
const gold = Color(0xFFD6AD55);
const blue = Color(0xFF4D9BE8);
const muted = Color(0xFF9BA8B7);
const green = Color(0xFF50C49A);
const red = Color(0xFFE36B70);

String nowStamp() =>
    DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());

String passHash(String s) => sha256.convert(utf8.encode(s)).toString();

const String _initialAdminSalt = 'Q2FyaW5vLTIuMy1hZG1pbi1zYWx0';
const String _initialAdminHash = '_xrJ8B25xUYoUK2ptAm0nJqMvHuU1PHiNFy6e5cV2Hk=';

bool _constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var difference = 0;
  for (var i = 0; i < a.length; i++) {
    difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return difference == 0;
}

String _newSalt() {
  final random = Random.secure();
  return base64UrlEncode(List<int>.generate(16, (_) => random.nextInt(256)));
}

String _passwordHash(String password, String salt) {
  // PBKDF2-HMAC-SHA256, 60,000 rounds. Legacy SHA-256 hashes are upgraded
  // automatically after the first successful login.
  final key = utf8.encode(password);
  final saltBytes = utf8.encode(salt);
  final hmac = Hmac(sha256, key);
  var u = hmac.convert([...saltBytes, 0, 0, 0, 1]).bytes;
  final result = List<int>.from(u);
  for (var i = 1; i < 60000; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < result.length; j++) {
      result[j] ^= u[j];
    }
  }
  return base64UrlEncode(result);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      size: Size(1280, 820),
      minimumSize: Size(980, 650),
      center: true,
      title: 'Engine Test Manager Pro 2.3',
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
      await windowManager.setAlwaysOnTop(false);
    });
    await localNotifier.setup(
      appName: 'Engine Test Manager Pro',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }
  await DB.instance.init();
  runApp(const MyApp());
}

class DB {
  DB._();
  static final instance = DB._();
  Database? db;

  Future<void> init() async {
    final base = Platform.isWindows
        ? (Platform.environment['APPDATA'] ?? Directory.current.path)
        : Directory.current.path;
    final dir = Directory(p.join(base, 'EngineTestManagerPro'));
    if (!await dir.exists()) await dir.create(recursive: true);

    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'engine_manager.db'),
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (d, v) async {
          await d.execute('''CREATE TABLE users(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            password_salt TEXT,
            display_name TEXT NOT NULL,
            role TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1)''');
          await d.execute('''CREATE TABLE shifts(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            document_no TEXT NOT NULL,
            shift_date TEXT NOT NULL,
            operator_name TEXT NOT NULL,
            operator_id INTEGER,
            status TEXT NOT NULL DEFAULT 'باز',
            created_at TEXT NOT NULL)''');
          await d.execute('''CREATE TABLE engines(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shift_id INTEGER NOT NULL,
            row_no INTEGER NOT NULL,
            engine_no TEXT NOT NULL,
            result TEXT NOT NULL,
            errors TEXT NOT NULL,
            notes TEXT NOT NULL,
            created_at TEXT NOT NULL,
            result_at TEXT,
            result_by TEXT)''');
          await d.insert('users', {
            'username': 'admin',
            'password_hash': _initialAdminHash,
            'password_salt': _initialAdminSalt,
            'display_name': 'مدیر سیستم',
            'role': 'admin',
            'active': 1,
          });
        },
        onUpgrade: (d, oldVersion, newVersion) async {
          // Preserve all existing 2.2 records; add only nullable/new columns.
          Future<bool> hasColumn(String table, String column) async {
            final cols = await d.rawQuery('PRAGMA table_info($table)');
            return cols.any((c) => c['name'] == column);
          }
          await d.execute('''CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, display_name TEXT NOT NULL,
            role TEXT NOT NULL, active INTEGER NOT NULL DEFAULT 1)''');
          await d.execute('''CREATE TABLE IF NOT EXISTS shifts(
            id INTEGER PRIMARY KEY AUTOINCREMENT, document_no TEXT NOT NULL,
            shift_date TEXT NOT NULL, operator_name TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'باز', created_at TEXT NOT NULL)''');
          await d.execute('''CREATE TABLE IF NOT EXISTS engines(
            id INTEGER PRIMARY KEY AUTOINCREMENT, shift_id INTEGER NOT NULL,
            row_no INTEGER NOT NULL, engine_no TEXT NOT NULL,
            result TEXT NOT NULL, errors TEXT NOT NULL, notes TEXT NOT NULL,
            created_at TEXT NOT NULL, result_at TEXT, result_by TEXT)''');
          if (!await hasColumn('users', 'password_salt')) {
            await d.execute('ALTER TABLE users ADD COLUMN password_salt TEXT');
          }
          if (!await hasColumn('shifts', 'operator_id')) {
            await d.execute('ALTER TABLE shifts ADD COLUMN operator_id INTEGER');
          }
          if (!await hasColumn('engines', 'result_at')) {
            await d.execute('ALTER TABLE engines ADD COLUMN result_at TEXT');
          }
          if (!await hasColumn('engines', 'result_by')) {
            await d.execute('ALTER TABLE engines ADD COLUMN result_by TEXT');
          }
          await d.execute('''CREATE TABLE IF NOT EXISTS users(
            id INTEGER PRIMARY KEY AUTOINCREMENT, username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL, password_salt TEXT,
            display_name TEXT NOT NULL, role TEXT NOT NULL,
            active INTEGER NOT NULL DEFAULT 1)''');
          await d.execute('''CREATE TABLE IF NOT EXISTS shifts(
            id INTEGER PRIMARY KEY AUTOINCREMENT, document_no TEXT NOT NULL,
            shift_date TEXT NOT NULL, operator_name TEXT NOT NULL,
            operator_id INTEGER, status TEXT NOT NULL DEFAULT 'باز',
            created_at TEXT NOT NULL)''');
          await d.execute('''CREATE TABLE IF NOT EXISTS engines(
            id INTEGER PRIMARY KEY AUTOINCREMENT, shift_id INTEGER NOT NULL,
            row_no INTEGER NOT NULL, engine_no TEXT NOT NULL,
            result TEXT NOT NULL, errors TEXT NOT NULL, notes TEXT NOT NULL,
            created_at TEXT NOT NULL)''');
          final admins = await d.query('users', where: 'username=?', whereArgs: ['admin']);
          if (admins.isEmpty) {
            await d.insert('users', {
              'username': 'admin', 'password_hash': _initialAdminHash,
              'password_salt': _initialAdminSalt, 'display_name': 'مدیر سیستم',
              'role': 'admin', 'active': 1,
            });
          }
        },
      ),
    );
  }

  Future<Map<String, Object?>?> login(String username, String password) async {
    final rows = await db!.query('users',
        where: 'username=? AND active=1', whereArgs: [username.trim()], limit: 1);
    if (rows.isEmpty) return null;
    final user = Map<String, Object?>.from(rows.first);
    final salt = user['password_salt'] as String?;
    bool valid;
    if (salt == null || salt.isEmpty) {
      valid = _constantTimeEquals('${user['password_hash']}', passHash(password));
      if (valid) {
        final newSalt = _newSalt();
        await db!.update('users', {
          'password_salt': newSalt,
          'password_hash': _passwordHash(password, newSalt),
        }, where: 'id=?', whereArgs: [user['id']]);
      }
    } else {
      valid = _constantTimeEquals('${user['password_hash']}', _passwordHash(password, salt));
    }
    return valid ? user : null;
  }

  Future<List<Map<String, Object?>>> shifts({required bool admin, int? userId}) {
    if (admin) return db!.query('shifts', orderBy: 'id DESC');
    return db!.query('shifts',
        where: 'operator_id=? AND status=?', whereArgs: [userId, 'باز'], orderBy: 'id DESC');
  }

  Future<Map<String, Object?>?> getShift(int id) async {
    final rows = await db!.query('shifts', where: 'id=?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<bool> canAccessShift(int id, int userId, bool admin) async {
    if (admin) return await getShift(id) != null;
    final rows = await db!.query('shifts',
        where: 'id=? AND operator_id=? AND status=?', whereArgs: [id, userId, 'باز'], limit: 1);
    return rows.isNotEmpty;
  }

  Future<List<Map<String, Object?>>> engines(int id) =>
      db!.query('engines', where: 'shift_id=?', whereArgs: [id], orderBy: 'row_no');

  Future<List<Map<String, Object?>>> pendingEngines(int shiftId) =>
      db!.query('engines', where: 'shift_id=? AND result=?',
          whereArgs: [shiftId, 'در انتظار'], orderBy: 'row_no');

  Future<int> createShift(String doc, String date, String op, int operatorId) =>
      db!.insert('shifts', {
        'document_no': doc, 'shift_date': date, 'operator_name': op,
        'operator_id': operatorId, 'status': 'باز', 'created_at': nowStamp(),
      });

  Future<void> closeShift(int id, {required bool pending, required int userId, required bool admin}) async {
    await _assertShiftAccess(id, userId, admin);
    await db!.update('shifts',
        {'status': pending ? 'بسته با موارد در انتظار' : 'بسته'},
        where: 'id=?', whereArgs: [id]);
  }

  Future<void> _assertShiftAccess(int shiftId, int userId, bool admin) async {
    if (!await canAccessShift(shiftId, userId, admin)) {
      throw StateError('دسترسی به این شیفت مجاز نیست');
    }
  }

  Future<int> add(
    Map<String, Object?> m, {required int userId, required bool admin}
  ) async {
    await _assertShiftAccess(m['shift_id'] as int, userId, admin);
    return await db!.insert('engines', m);
  }

  Future<void> update(
    int id, Map<String, Object?> m, {required int userId, required bool admin}
  ) async {
    final rows = await db!.query('engines', columns: ['shift_id'],
        where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) throw StateError('رکورد موتور پیدا نشد');
    final ownerShiftId = rows.first['shift_id'] as int;
    await _assertShiftAccess(ownerShiftId, userId, admin);
    if (m['shift_id'] != null && m['shift_id'] != ownerShiftId) {
      throw StateError('انتقال رکورد بین شیفت‌ها مجاز نیست');
    }
    await db!.update('engines', m, where: 'id=?', whereArgs: [id]);
  }

  Future<void> delete(
    int id, {required int userId, required bool admin}
  ) async {
    final rows = await db!.query('engines', columns: ['shift_id'],
        where: 'id=?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    await _assertShiftAccess(rows.first['shift_id'] as int, userId, admin);
    await db!.delete('engines', where: 'id=?', whereArgs: [id]);
  }
  Future<List<Map<String, Object?>>> operatorSummary() => db!.rawQuery('''
    SELECT s.operator_id, s.operator_name,
      COUNT(DISTINCT s.id) AS shift_count,
      COUNT(e.id) AS engine_count,
      SUM(CASE WHEN e.result='سالم' THEN 1 ELSE 0 END) AS ok_count,
      SUM(CASE WHEN e.result='مردود' THEN 1 ELSE 0 END) AS nok_count,
      SUM(CASE WHEN e.result='نیازمند بررسی' THEN 1 ELSE 0 END) AS review_count,
      SUM(CASE WHEN e.result='در انتظار' THEN 1 ELSE 0 END) AS pending_count
    FROM shifts s LEFT JOIN engines e ON e.shift_id=s.id
    GROUP BY s.operator_id, s.operator_name ORDER BY engine_count DESC
  ''');

  Future<List<Map<String, Object?>>> users() => db!.query('users', orderBy: 'id');

  Future<void> saveUser({
    int? id, required String username, required String name,
    required String password, required String role, required bool active,
  }) async {
    if (username.trim().isEmpty || name.trim().isEmpty) {
      throw Exception('نام و نام کاربری الزامی است');
    }
    final m = <String, Object?>{
      'username': username.trim(), 'display_name': name.trim(),
      'role': role, 'active': active ? 1 : 0,
    };
    if (password.isNotEmpty) {
      final salt = _newSalt();
      m['password_salt'] = salt;
      m['password_hash'] = _passwordHash(password, salt);
    }
    if (id == null) {
      if (password.isEmpty) throw Exception('رمز عبور الزامی است');
      await db!.insert('users', m);
    } else {
      await db!.update('users', m, where: 'id=?', whereArgs: [id]);
    }
  }
}

// ================= APPLICATION =================

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Map<String, Object?>? user;

  @override
  Widget build(BuildContext c) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Engine Test Manager Pro',
      theme: ThemeData.dark(
        useMaterial3: true,
      ).copyWith(
        scaffoldBackgroundColor: bg,
        colorScheme: const ColorScheme.dark(
          primary: gold,
          secondary: blue,
          surface: panel,
        ),
        cardColor: panel,
        dividerColor: panel2,
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: panel2,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      builder: (c, w) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: w ?? const SizedBox.shrink(),
        );
      },
      home: user == null
          ? Login(
              onLogin: (u) => setState(() => user = u),
            )
          : Shell(
              user: user!,
              logout: () => setState(() => user = null),
            ),
    );
  }
}

// ================= LOGIN =================

class Login extends StatefulWidget {
  final ValueChanged<Map<String, Object?>> onLogin;

  const Login({
    super.key,
    required this.onLogin,
  });

  @override
  State<Login> createState() => _LoginState();
}

class _LoginState extends State<Login> {
  final u = TextEditingController();
  final pw = TextEditingController();

  String error = '';
  TextEditingController? active;
  bool english = false;
  bool englishDigits = true;
  bool showPassword = false;
  bool keyboardVisible = true;

  void insertKey(String value) {
    final target = active ?? u;
    final old = target.value;
    final start = old.selection.isValid ? old.selection.start : old.text.length;
    final end = old.selection.isValid ? old.selection.end : old.text.length;
    final next = value == '⌫'
        ? (start == end && start > 0
            ? old.text.replaceRange(start - 1, end, '')
            : old.text.replaceRange(start, end, ''))
        : old.text.replaceRange(start, end, value);
    final cursor = value == '⌫' ? (start == end && start > 0 ? start - 1 : start) : start + value.length;
    target.value = TextEditingValue(
      text: next, selection: TextSelection.collapsed(offset: cursor.clamp(0, next.length) as int),
    );
    setState(() {});
  }

  Widget keyboardKey(String label, {double width = 30, VoidCallback? onTap}) {
    return SizedBox(
      width: width, height: 36,
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(padding: EdgeInsets.zero,
            minimumSize: Size.zero, visualDensity: VisualDensity.compact),
          onPressed: onTap ?? () => insertKey(label),
          child: Text(label, style: const TextStyle(fontSize: 14)),
        ),
      ),
    );
  }

  Future<void> go() async {
    final x = await DB.instance.login(u.text, pw.text);

    if (!mounted) return;

    if (x == null) {
      setState(() {
        error = 'نام کاربری یا رمز اشتباه است';
      });
    } else {
      widget.onLogin(x);
    }
  }

  @override
  void dispose() {
    u.dispose();
    pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    return Scaffold(
      body: Center(
        child: Container(
          width: 390,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: panel,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: gold.withValues(alpha: .4),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.precision_manufacturing,
                color: gold,
                size: 52,
              ),
              const SizedBox(height: 12),
              const Text(
                'ENGINE TEST MANAGER',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const Text(
                'PRO 2.3',
                style: TextStyle(
                  color: gold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 25),
              TextField(
                controller: u,
                readOnly: true,
                onTap: () => setState(() { active = u; keyboardVisible = true; }),
                decoration: const InputDecoration(labelText: 'نام کاربری'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw,
                readOnly: true,
                obscureText: !showPassword,
                onTap: () => setState(() { active = pw; keyboardVisible = true; }),
                decoration: InputDecoration(
                  labelText: 'رمز عبور',
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => showPassword = !showPassword),
                    icon: Icon(showPassword ? Icons.visibility_off : Icons.visibility),
                  ),
                ),
              ),
              if (keyboardVisible) ...[
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: [
                    keyboardKey(english ? 'فارسی' : 'EN', width: 54,
                      onTap: () => setState(() => english = !english)),
                    keyboardKey(englishDigits ? '۱۲۳' : '123', width: 54,
                      onTap: () => setState(() => englishDigits = !englishDigits)),
                    keyboardKey('⌫', width: 48),
                    keyboardKey('فاصله', width: 58, onTap: () => insertKey(' ')),
                    keyboardKey('پاک', width: 42, onTap: () { (active ?? u).clear(); setState(() {}); }),
                  ],
                ),
                const SizedBox(height: 3),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: (english
                    ? 'qwertyuiopasdfghjklzxcvbnm'.split('')
                    : 'ضصثقفغعهخحجچشسیبلاتنمکگظطزرذدپوژآئء'.split(''))
                    .map((k) => keyboardKey(k)).toList(),
                ),
                Wrap(
                  alignment: WrapAlignment.center,
                  children: (englishDigits ? '1234567890' : '۱۲۳۴۵۶۷۸۹۰')
                    .split('').map((k) => keyboardKey(k)).toList(),
                ),
              ],
              if (error.isNotEmpty)
                Text(
                  error,
                  style: const TextStyle(color: red),
                ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: go,
                  child: const Text('ورود'),
                ),
              ),
              const SizedBox(height: 8),
              const Text('صفحه‌کلید داخلی برنامه', style: TextStyle(color: muted, fontSize: 10)),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= MAIN SHELL =================

class Shell extends StatefulWidget {
  final Map<String, Object?> user;
  final VoidCallback logout;

  const Shell({
    super.key,
    required this.user,
    required this.logout,
  });

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int tab = 0;

  List<Map<String, Object?>> shifts = [];

  bool get admin => widget.user['role'] == 'admin';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await DB.instance.shifts(
      admin: admin, userId: widget.user['id'] as int,
    );

    if (mounted) {
      setState(() {
        shifts = result;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final pages = <Widget>[
      Dashboard(
        shifts: shifts,
        refresh: load,
        open: open,
        admin: admin,
        operatorName: '${widget.user['display_name']}',
        operatorId: widget.user['id'] as int,
      ),
      if (admin) Archive(shifts: shifts, open: open),
      if (admin) const Users(),
    ];

    final idx = tab < pages.length ? tab : 0;

    return Scaffold(
      body: Row(
        children: [
          Container(
            width: 220,
            color: const Color(0xFF0D121A),
            padding: const EdgeInsets.all(17),
            child: Column(
              children: [
                const Icon(
                  Icons.precision_manufacturing,
                  color: gold,
                  size: 42,
                ),
                const Text(
                  'ENGINE TEST',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                const Text(
                  'MANAGER PRO',
                  style: TextStyle(
                    color: gold,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 30),
                nav(0, Icons.dashboard, 'داشبورد'),
                if (admin) nav(1, Icons.archive, 'سوابق و گزارش‌ها'),
                if (admin) nav(2, Icons.manage_accounts, 'مدیریت کاربران'),
                const Spacer(),
                Text(
                  '${widget.user['display_name']} • '
                  '${admin ? 'مدیر' : 'اپراتور'}',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                  ),
                ),
                TextButton.icon(
                  onPressed: widget.logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('خروج'),
                ),
                const Text(
                  'توسعه‌دهنده: حامد سیدفقیر',
                  style: TextStyle(color: muted, fontSize: 10),
                ),
                const SizedBox(height: 5),
                const Text(
                  'ذخیره‌سازی محلی فعال',
                  style: TextStyle(
                    color: green,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: pages[idx]),
        ],
      ),
    );
  }

  Widget nav(int i, IconData icon, String title) {
    return ListTile(
      selected: tab == i,
      selectedTileColor: gold.withValues(alpha: .13),
      leading: Icon(
        icon,
        color: tab == i ? gold : muted,
      ),
      title: Text(title),
      onTap: () => setState(() => tab = i),
    );
  }

  Future<void> open(Map<String, Object?> s) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ShiftPage(
          shift: s, user: widget.user, admin: admin,
        ),
      ),
    );

    await load();
  }
}

// ================= DASHBOARD =================

class Dashboard extends StatelessWidget {
  final List<Map<String, Object?>> shifts;
  final VoidCallback refresh;
  final ValueChanged<Map<String, Object?>> open;
  final bool admin;
  final String operatorName;
  final int operatorId;

  const Dashboard({
    super.key,
    required this.shifts,
    required this.refresh,
    required this.open,
    required this.admin,
    required this.operatorName,
    required this.operatorId,
  });

  @override
  Widget build(BuildContext c) {
    final op = shifts.where(
      (s) => s['status'] == 'باز',
    ).length;

    return Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'داشبورد مدیریت تست موتور',
                      style: TextStyle(
                        fontSize: 25,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'ثبت و ردیابی نتایج تست موتورهای TU5',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('بروزرسانی'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => create(c, refresh, open, operatorName, operatorId),
                icon: const Icon(Icons.add),
                label: const Text('شروع شیفت جدید'),
              ),
            ],
          ),
          if (admin) ...[
            const SizedBox(height: 24),
            Wrap(spacing: 12, children: [
              stat('کل فرم‌ها', shifts.length, gold),
              stat('شیفت باز', op, green),
              stat('شیفت بسته', shifts.length - op, blue),
            ]),
            const SizedBox(height: 22),
            const Text('آخرین شیفت‌ها', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ] else ...[
            const SizedBox(height: 24),
            const Text('شیفت فعال من', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
          if (admin) SizedBox(
            height: 122,
            child: FutureBuilder<List<Map<String, Object?>>>(
              future: DB.instance.operatorSummary(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? [];
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: LinearProgressIndicator());
                }
                if (data.isEmpty) return const Center(child: Text('هنوز داده‌ای برای گزارش عملکرد وجود ندارد', style: TextStyle(color: muted)));
                return ListView(scrollDirection: Axis.horizontal, children: data.map((r) => Container(
                  width: 205, margin: const EdgeInsets.only(left: 8), padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: panel, borderRadius: BorderRadius.circular(10), border: Border.all(color: panel2)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text('${r['operator_name']}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('شیفت: ${r['shift_count']}  |  موتور: ${r['engine_count']}', style: const TextStyle(fontSize: 11, color: muted)),
                    Text('قبول: ${r['ok_count'] ?? 0}  مردود: ${r['nok_count'] ?? 0}', style: const TextStyle(fontSize: 11)),
                    Text('بررسی: ${r['review_count'] ?? 0}  انتظار: ${r['pending_count'] ?? 0}', style: const TextStyle(fontSize: 11, color: muted)),
                  ]),
                )).toList());
              },
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: shifts.isEmpty
                ? const Center(
                    child: Text(
                      'هنوز فرمی ثبت نشده است',
                      style: TextStyle(color: muted),
                    ),
                  )
                : ListView(
                    children: shifts.map((s) {
                      return Card(
                        child: ListTile(
                          leading: const Icon(
                            Icons.assignment,
                            color: gold,
                          ),
                          title: Text(
                            'سند ${s['document_no']} • '
                            '${s['operator_name']}',
                          ),
                          subtitle: Text(
                            '${s['shift_date']} | ${s['status']}',
                          ),
                          onTap: () => open(s),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget stat(String t, int v, Color color) {
    return Container(
      width: 175,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: panel2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$v',
            style: TextStyle(
              fontSize: 26,
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            t,
            style: const TextStyle(color: muted),
          ),
        ],
      ),
    );
  }

  static Future<void> create(
    BuildContext c, VoidCallback refresh,
    ValueChanged<Map<String, Object?>> open,
    String operatorName, int operatorId,
  ) async {
    final doc = TextEditingController(
      text: 'ET-${DateTime.now().millisecondsSinceEpoch % 1000000}',
    );

    final date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );

    final ok = await showDialog<bool>(
      context: c,
      builder: (x) => AlertDialog(
        title: const Text('فرم شیفت جدید'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: doc,
                decoration: const InputDecoration(
                  labelText: 'شماره سند',
                ),
              ),
              TextField(
                controller: date,
                decoration: const InputDecoration(
                  labelText: 'تاریخ (میلادی)',
                ),
              ),
              ListTile(leading: const Icon(Icons.person), title: Text(operatorName), subtitle: const Text('اپراتور ثبت‌کننده شیفت')), 
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('ایجاد'),
          ),
        ],
      ),
    );

    if (ok != true || doc.text.trim().isEmpty) {
      doc.dispose();
      date.dispose();
      return;
    }

    final id = await DB.instance.createShift(
      doc.text,
      date.text,
      operatorName, operatorId,
    );

    final documentNo = doc.text;
    doc.dispose();
    date.dispose();

    refresh();
    if (Platform.isWindows) {
      try {
        LocalNotification(
          title: 'شیفت جدید ایجاد شد',
          body: 'سند $documentNo برای اپراتور $operatorName',
        ).show();
      } catch (_) {}
    }
    final s = (await DB.instance.shifts(admin: true)).firstWhere(
      (e) => e['id'] == id,
    );

    open(s);
  }
}

// ================= ARCHIVE =================

class Archive extends StatefulWidget {
  final List<Map<String, Object?>> shifts;
  final ValueChanged<Map<String, Object?>> open;

  const Archive({
    super.key,
    required this.shifts,
    required this.open,
  });

  @override
  State<Archive> createState() => _ArchiveState();
}

class _ArchiveState extends State<Archive> {
  String q = '';

  @override
  Widget build(BuildContext c) {
    final list = widget.shifts.where((s) {
      return '${s['document_no']} '
          '${s['operator_name']} '
          '${s['shift_date']}'
          .toLowerCase()
          .contains(q.toLowerCase());
    }).toList();

    return Padding(
      padding: const EdgeInsets.all(25),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'فایل‌های ذخیره‌شده',
            style: TextStyle(
              fontSize: 25,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: 360,
            child: TextField(
              onChanged: (v) => setState(() => q = v),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'جست‌وجوی سند، اپراتور یا تاریخ',
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: list.map((s) {
                return Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.inventory,
                      color: gold,
                    ),
                    title: Text(
                      'سند ${s['document_no']} • '
                      '${s['operator_name']}',
                    ),
                    subtitle: Text(
                      '${s['shift_date']} | ${s['status']}',
                    ),
                    onTap: () => widget.open(s),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

const Map<String, List<String>> engineErrorCategories = {
  'ایرادات صوتی': ['صدای شدید کاور', 'صدای سرسیلندر', 'صدای شدید سرسیلندر', 'صدای شدید بلوکه سیلندر'],
  'ایرادات نشتی': ['نشتی روغن', 'نشتی آب', 'نشتی بنزین'],
  'ایرادات مکانیکی/مونتاژی': [
    'ایراد مونتاژی یا شکستگی', 'عدم احتراق (موتور سه‌سیلندر کار می‌کند)',
    'عدم تعادل', 'عدم کمپرس', 'عدم ترموستات', 'فاقد شماره موتور',
  ],
  'خطای سنسورها': ['اکسیژن', 'انژکتور', 'کوئل', 'دمای آب', 'فشار روغن', 'دور موتور', 'دریچه گاز', 'CVVT'],
};

// ================= SHIFT PAGE =================

class ShiftPage extends StatefulWidget {
  final Map<String, Object?> shift;
  final Map<String, Object?> user;
  final bool admin;

  const ShiftPage({
    super.key, required this.shift, required this.user, required this.admin,
  });

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> with WidgetsBindingObserver {
  List<Map<String, Object?>> rows = [];

  final TextEditingController _scanController = TextEditingController();
  final FocusNode _scanFocus = FocusNode();

  String q = '';
  bool _resultDialogOpen = false;
  bool _scanProcessing = false;
  final Queue<String> _scanQueue = Queue<String>();
  static const MethodChannel _barcodeChannel = MethodChannel('engine_test_manager/barcode');

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeChannel.setMethodCallHandler(null);
    _scanController.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  void _enqueueBarcode(String value) {
    final code = value.trim();
    if (code.isEmpty || _scanQueue.length >= 100) return;
    _scanQueue.addLast(code);
    if (!_scanProcessing) unawaited(_processScanQueue());
  }

  Future<void> _processScanQueue() async {
    if (_scanProcessing) return;
    _scanProcessing = true;
    try {
      while (mounted && _scanQueue.isNotEmpty) {
        await _submitScannedBarcode(_scanQueue.removeFirst());
      }
    } finally {
      _scanProcessing = false;
      if (mounted && _scanQueue.isNotEmpty) unawaited(_processScanQueue());
    }
  }

  Future<void> _submitScannedBarcode(String value) async {
    final code = value.trim();
    _scanController.clear();
    if (code.isEmpty || closed || rows.length >= 80) {
      if (mounted) _scanFocus.requestFocus();
      return;
    }
    if (rows.any((r) => r['engine_no'] == code)) {
      _notify('بارکد تکراری', 'شماره موتور $code قبلاً در این شیفت ثبت شده است.');
      if (mounted) _scanFocus.requestFocus();
      return;
    }
    final used = rows.map((r) => r['row_no'] as int).toSet();
    final rowNo = List<int>.generate(80, (i) => i + 1)
        .firstWhere((v) => !used.contains(v));
    await DB.instance.add({
      'shift_id': widget.shift['id'], 'row_no': rowNo,
      'engine_no': code, 'result': 'در انتظار', 'errors': '',
      'notes': '', 'created_at': nowStamp(), 'result_at': null, 'result_by': null,
    }, userId: widget.user['id'] as int, admin: widget.admin);
    await load();
    final pending = await DB.instance.pendingEngines(widget.shift['id'] as int);
    _notify('موتور جدید اسکن شد', 'شماره $code ثبت شد.');
    // The previous engine is queued. Do not steal focus from the factory app.
    if (pending.length > 1 && mounted) {
      _notifyPending(pending.first);
      final focused = Platform.isWindows ? await windowManager.isFocused() : true;
      if (focused) await _showNextPending();
    }
    if (mounted) _scanFocus.requestFocus();
  }

  bool get closed => widget.shift['status'] != 'باز';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeChannel.setMethodCallHandler((call) async {
      if (call.method == 'barcode' && call.arguments is String && mounted && !closed) {
        _enqueueBarcode(call.arguments as String);
      }
    });
    load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _showNextPending();
  }

  Future<void> _showNextPending() async {
    if (!mounted || closed || _resultDialogOpen) return;
    final pending = await DB.instance.pendingEngines(widget.shift['id'] as int);
    if (pending.length > 1 && mounted && !_resultDialogOpen) {
      _resultDialogOpen = true;
      bool saved = false;
      try { saved = await resolvePending(pending.first); } finally { _resultDialogOpen = false; }
      if (saved && mounted) {
        final remaining = await DB.instance.pendingEngines(widget.shift['id'] as int);
        if (remaining.length > 1) {
          Future<void>.delayed(const Duration(milliseconds: 180), _showNextPending);
        }
      }
    }
  }

  Future<void> load() async {
    final allowed = await DB.instance.canAccessShift(
      widget.shift['id'] as int, widget.user['id'] as int, widget.admin,
    );
    if (!allowed) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final result = await DB.instance.engines(widget.shift['id'] as int);

    if (mounted) {
      setState(() {
        rows = result;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final shown = rows.where((r) {
      return '${r['engine_no']}'.contains(q);
    }).toList();

    final ok = rows.where(
      (r) => r['result'] == 'سالم',
    ).length;

    final nok = rows.where(
      (r) => r['result'] == 'مردود',
    ).length;

    final rev = rows.where(
      (r) => r['result'] == 'نیازمند بررسی',
    ).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'فرم شیفت • ${widget.shift['document_no']}',
        ),
        actions: [
          if (!closed) TextButton.icon(
            onPressed: saveAndExit, icon: const Icon(Icons.save_alt),
            label: const Text('ذخیره و خروج'),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                info('تاریخ', '${widget.shift['shift_date']}'),
                info('اپراتور', '${widget.shift['operator_name']}'),
                info('تعداد', '${rows.length}/80'),
                info('سالم', '$ok'),
                info('مردود', '$nok'),
                info('بررسی', '$rev'),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => q = v),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'جست‌وجوی شماره موتور',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (!closed)
                  SizedBox(
                    width: 300,
                    child: TextField(
                      controller: _scanController,
                      focusNode: _scanFocus,
                      readOnly: true,
                      autofocus: false,
                      textInputAction: TextInputAction.done,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.qr_code_scanner),
                        labelText: 'اسکن بارکد بعدی',
                        hintText: 'دریافت خودکار بارکد در پس‌زمینه فعال است',
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                if (!closed)
                  FilledButton.icon(
                    onPressed: rows.length >= 80 ? null : () => edit(),
                    icon: const Icon(Icons.edit_note),
                    label: const Text('ثبت دستی'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(
                      children: shown
                          .take((shown.length / 2).ceil())
                          .map(card)
                          .toList(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ListView(
                      children: shown
                          .skip((shown.length / 2).ceil())
                          .map(card)
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: closed ? null : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
          child: Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: saveAndExit,
              icon: const Icon(Icons.save_alt),
              label: const Text('ذخیره و خروج'),
            ),
          ),
        ),
      ),
    );
  }

  Widget info(String a, String b) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$a: $b',
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget card(Map<String, Object?> r) {
    return Card(
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: gold.withValues(alpha: .15),
          child: Text(
            '${r['row_no']}',
            style: const TextStyle(color: gold),
          ),
        ),
        title: Text(
          '${r['engine_no']}',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Text(
          '${r['result']} • ${r['errors']}\n'
          '${r['result_at'] ?? r['created_at']} • ${r['result_by'] ?? widget.shift['operator_name']}',
          maxLines: 2, overflow: TextOverflow.ellipsis,
        ),
        trailing: closed
            ? null
            : PopupMenuButton<String>(
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'e',
                    child: Text('ویرایش'),
                  ),
                  PopupMenuItem(
                    value: 'd',
                    child: Text('حذف'),
                  ),
                  PopupMenuItem(
                    value: 'm',
                    child: Text('انتقال ردیف'),
                  ),
                ],
                onSelected: (v) {
                  if (v == 'e') edit(row: r);
                  if (v == 'd') remove(r);
                  if (v == 'm') move(r);
                },
              ),
      ),
    );
  }

  Future<void> edit({
    Map<String, Object?>? row,
    String initialBarcode = '',
  }) async {
    final no = TextEditingController(
      text: row?['engine_no']?.toString() ?? initialBarcode,
    );

    final notes = TextEditingController(
      text: '${row?['notes'] ?? ''}',
    );

    String result = '${row?['result'] ?? 'در انتظار'}';
    String category = engineErrorCategories.keys.first;
    String selectedError = '';
    final existingError = '${row?['errors'] ?? ''}';
    final existingErrorName = existingError.contains(' | ')
        ? existingError.split(' | ').last : existingError;
    for (final entry in engineErrorCategories.entries) {
      if (entry.value.contains(existingErrorName)) { category = entry.key; selectedError = existingErrorName; }
    }

    final d = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (x, setD) => AlertDialog(
          title: Text(
            row == null ? 'ثبت موتور' : 'ویرایش موتور',
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: no,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'شماره موتور / بارکد',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: result,
                  decoration: const InputDecoration(
                    labelText: 'نتیجه',
                  ),
                  items: [
                    'در انتظار',
                    'سالم',
                    'مردود',
                    'نیازمند بررسی',
                  ].map((v) {
                    return DropdownMenuItem(
                      value: v,
                      child: Text(v),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setD(() { result = v ?? result; if (result != 'مردود') { selectedError = ''; } });
                  },
                ),
                if (result == 'مردود') ...[
                  DropdownButtonFormField<String>(
                    value: category, decoration: const InputDecoration(labelText: 'دسته‌بندی ایراد'),
                    items: engineErrorCategories.keys.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setD(() { category = v ?? category; selectedError = ''; }),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: selectedError.isEmpty ? null : selectedError,
                    decoration: const InputDecoration(labelText: 'نوع ایراد'),
                    items: engineErrorCategories[category]!.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                    onChanged: (v) => setD(() { selectedError = v ?? ''; }),
                  ),
                ],
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'توضیحات',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x),
              child: const Text('انصراف'),
            ),
            FilledButton(
              onPressed: () {
                if (result == 'مردود' && selectedError.isEmpty) return;
                Navigator.pop(x, {
                  'engine_no': no.text.trim(),
                  'result': result,
                  'errors': result == 'مردود' ? '$category | $selectedError' : '',
                  'notes': notes.text.trim(),
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    no.dispose();
    notes.dispose();

    // The dialog is asynchronous; verify this page is still mounted
    // before opening another dialog or using its BuildContext.
    if (!mounted) return;

    if (d == null) return;
    if ('${d['engine_no']}'.isEmpty) {
      if (d['result'] == 'مردود' && selectedError == 'فاقد شماره موتور') {
        d['engine_no'] = 'فاقد شماره موتور-${DateTime.now().millisecondsSinceEpoch}';
      } else {
        return;
      }
    }

    final duplicate = rows.any(
      (r) =>
          r['engine_no'] == d['engine_no'] &&
          r['id'] != row?['id'],
    );

    Map<String, Object?>? duplicateRow;
    if (duplicate) {
      duplicateRow = rows.firstWhere(
        (r) => r['engine_no'] == d['engine_no'] && r['id'] != row?['id'],
      );
      final choice = await showDialog<String>(
        context: context,
        builder: (x) => AlertDialog(
          title: const Text('بارکد تکراری'),
          content: Text('شماره ${d['engine_no']} قبلاً در این فرم ثبت شده است.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(x, 'rescan'),
              child: const Text('ثبت ازنو')),
            OutlinedButton(onPressed: () => Navigator.pop(x, 'replace'),
              child: const Text('جایگزینی با شماره قبلی')),
            FilledButton(onPressed: () => Navigator.pop(x, 'again'),
              child: const Text('ثبت مجددا')),
          ],
        ),
      );
      if (choice == null || choice == 'rescan') return;
      if (choice == 'replace') {
        final replacement = <String, Object?>{
          'shift_id': widget.shift['id'],
          'row_no': duplicateRow!['row_no'],
          ...d,
          'created_at': nowStamp(),
          'result_at': d['result'] == 'در انتظار' ? null : nowStamp(),
          'result_by': d['result'] == 'در انتظار' ? null : widget.user['display_name'],
        };
        await DB.instance.update(duplicateRow!['id'] as int, replacement, userId: widget.user['id'] as int, admin: widget.admin);
        await load();
        _notify('نتیجه تست جایگزین شد',
          'رکورد قبلی بارکد ${d['engine_no']} به‌روزرسانی شد.');
        return;
      }
      // 'again' creates a new row with the same barcode.
    }

    final used = rows
        .map((r) => r['row_no'] as int)
        .toSet();

    final n = (row?['row_no'] as int?) ??
        List<int>.generate(80, (i) => i + 1)
            .firstWhere((v) => !used.contains(v));

    final m = <String, Object?>{
      'shift_id': widget.shift['id'],
      'row_no': n,
      ...d,
      'created_at': row?['created_at'] ?? nowStamp(),
      'result_at': d['result'] == 'در انتظار' ? null : nowStamp(),
      'result_by': d['result'] == 'در انتظار' ? null : widget.user['display_name'],
    };

    if (row == null) {
      await DB.instance.add(m, userId: widget.user['id'] as int, admin: widget.admin);
    } else {
      await DB.instance.update(
        row['id'] as int, m, userId: widget.user['id'] as int, admin: widget.admin,
      );
    }

    await load();
    _notify(row == null ? 'موتور ثبت شد' : 'رکورد ویرایش شد',
      'شماره موتور: ${d['engine_no']}');
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scanFocus.requestFocus();
      });
    }
  }

  Future<bool> resolvePending(Map<String, Object?> engine, {String? initialResult}) async {
    String result = initialResult ?? 'سالم';
    String category = engineErrorCategories.keys.first;
    String error = '';
    final chosen = await showDialog<Map<String, String>?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setD) => AlertDialog(
          title: const Text('تعیین وضعیت موتور قبلی'),
          content: SizedBox(
            width: 430,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('شماره موتور: ${engine['engine_no']}', style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: result, decoration: const InputDecoration(labelText: 'وضعیت تست'),
                items: const [
                  DropdownMenuItem(value: 'سالم', child: Text('قبول (OK)')),
                  DropdownMenuItem(value: 'مردود', child: Text('مردود (NOK)')),
                  DropdownMenuItem(value: 'نیازمند بررسی', child: Text('نیازمند بررسی (Review)')),
                ],
                onChanged: (v) => setD(() { result = v ?? result; if (result != 'مردود') error = ''; }),
              ),
              if (result == 'مردود') ...[
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: category, decoration: const InputDecoration(labelText: 'دسته‌بندی ایراد'),
                  items: engineErrorCategories.keys.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setD(() { category = v ?? category; error = ''; }),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: error.isEmpty ? null : error,
                  decoration: const InputDecoration(labelText: 'نوع ایراد'),
                  items: engineErrorCategories[category]!.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setD(() => error = v ?? ''),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('بعداً')),
            FilledButton(onPressed: () {
              if (result == 'مردود' && error.isEmpty) return;
              Navigator.pop(dialogContext, {
                'result': result, 'error': result == 'مردود' ? '$category | $error' : '',
              });
            }, child: const Text('ثبت نتیجه')),
          ],
        ),
      ),
    );
    if (chosen == null) return false;
    await DB.instance.update(engine['id'] as int, {
      ...engine, 'result': chosen['result']!, 'errors': chosen['error']!,
      'created_at': engine['created_at'],
      'result_at': nowStamp(), 'result_by': widget.user['display_name'],
    }, userId: widget.user['id'] as int, admin: widget.admin);
    await load();
    _notify('نتیجه موتور ذخیره شد', 'موتور ${engine['engine_no']}: ${chosen['result']}');
    return true;
  }

  void _notifyPending(Map<String, Object?> engine) {
    if (!Platform.isWindows) return;
    try {
      final notification = LocalNotification(
        title: 'تعیین وضعیت موتور قبلی',
        body: 'موتور ${engine['engine_no']} هنوز نتیجه نهایی ندارد.',
        actions: [
          LocalNotificationAction(text: 'قبول (OK)'),
          LocalNotificationAction(text: 'مردود (NOK)'),
          LocalNotificationAction(text: 'نیازمند بررسی'),
          LocalNotificationAction(text: 'ذخیره و خروج'),
        ],
      );
      notification.onClick = () => unawaited(_openAndResolve(engine));
      notification.onClickAction = (index) {
        if (index == 0) {
          unawaited(_savePendingQuick(engine, 'سالم'));
        } else if (index == 1) {
          unawaited(_openAndResolve(engine, initialResult: 'مردود'));
        } else if (index == 2) {
          unawaited(_savePendingQuick(engine, 'نیازمند بررسی'));
        } else if (index == 3) {
          unawaited(_openAndSaveExit());
        }
      };
      notification.show();
    } catch (_) {}
  }

  Future<void> _openAndSaveExit() async {
    await windowManager.show();
    await windowManager.focus();
    if (mounted) await saveAndExit();
  }

  Future<void> _openAndResolve(
    Map<String, Object?> engine, {String? initialResult}
  ) async {
    await windowManager.show();
    await windowManager.focus();
    if (mounted) {
      final saved = await resolvePending(engine, initialResult: initialResult);
      if (saved && mounted) {
        final remaining = await DB.instance.pendingEngines(widget.shift['id'] as int);
        if (remaining.length > 1) await _showNextPending();
      }
    }
  }

  Future<void> _savePendingQuick(
    Map<String, Object?> engine, String result
  ) async {
    await DB.instance.update(engine['id'] as int, {
      ...engine, 'result': result, 'errors': '',
      'result_at': nowStamp(), 'result_by': widget.user['display_name'],
    }, userId: widget.user['id'] as int, admin: widget.admin);
    await load();
    _notify('نتیجه موتور ذخیره شد', 'موتور ${engine['engine_no']}: $result');
    final pending = await DB.instance.pendingEngines(widget.shift['id'] as int);
    if (pending.length > 1) _notifyPending(pending.first);
  }

  void _notify(String title, String body) {
    if (!Platform.isWindows) return;
    try {
      LocalNotification(title: title, body: body).show();
    } catch (_) {}
  }

  Future<void> remove(Map<String, Object?> r) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('حذف رکورد'),
        content: Text(
          'موتور ${r['engine_no']} حذف شود؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('انصراف'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (yes == true) {
      await DB.instance.delete(r['id'] as int, userId: widget.user['id'] as int, admin: widget.admin);
      await load();
    }
  }

  Future<void> move(Map<String, Object?> r) async {
    final t = TextEditingController(
      text: '${r['row_no']}',
    );

    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('انتقال ردیف'),
        content: TextField(
          controller: t,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'شماره ردیف ۱ تا ۸۰',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('انتقال'),
          ),
        ],
      ),
    );

    final n = int.tryParse(t.text);
    t.dispose();

    if (yes == true &&
        n != null &&
        n > 0 &&
        n <= 80 &&
        !rows.any(
          (e) => e['row_no'] == n && e['id'] != r['id'],
        )) {
      await DB.instance.update(
        r['id'] as int, {...r, 'row_no': n},
        userId: widget.user['id'] as int, admin: widget.admin,
      );

      await load();
    }
  }

  Future<void> saveAndExit() async {
    var pending = await DB.instance.pendingEngines(widget.shift['id'] as int);
    if (pending.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (x) => AlertDialog(
          title: const Text('موتورهای تعیین‌تکلیف‌نشده'),
          content: Text('${pending.length} موتور هنوز نتیجه نهایی ندارند. می‌خواهید تعیین وضعیت کنید یا با وضعیت انتظار ذخیره و خارج شوید؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(x, 'cancel'), child: const Text('بازگشت به شیفت')),
            OutlinedButton(onPressed: () => Navigator.pop(x, 'keep'), child: const Text('ذخیره با وضعیت انتظار')),
            FilledButton(onPressed: () => Navigator.pop(x, 'resolve'), child: const Text('تعیین وضعیت')),
          ],
        ),
      );
      if (choice == null || choice == 'cancel') return;
      if (choice == 'resolve') {
        for (final engine in pending) {
          await resolvePending(engine);
        }
        pending = await DB.instance.pendingEngines(widget.shift['id'] as int);
        if (pending.isNotEmpty) {
          final keep = await showDialog<bool>(
            context: context,
            builder: (x) => AlertDialog(
              title: const Text('موارد باقی‌مانده'),
              content: Text('${pending.length} موتور همچنان در انتظار است. با همین وضعیت ذخیره شود؟'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(x, false), child: const Text('ادامه شیفت')),
                FilledButton(onPressed: () => Navigator.pop(x, true), child: const Text('ذخیره و خروج')),
              ],
            ),
          );
          if (keep != true) return;
        }
      }
    }
    final stillPending = (await DB.instance.pendingEngines(widget.shift['id'] as int)).isNotEmpty;
    await DB.instance.closeShift(widget.shift['id'] as int, pending: stillPending, userId: widget.user['id'] as int, admin: widget.admin);
    if (Platform.isWindows) {
      await windowManager.close();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

}

// ================= USER MANAGEMENT =================

class Users extends StatefulWidget {
  const Users({super.key});

  @override
  State<Users> createState() => _UsersState();
}

class _UsersState extends State<Users> {
  List<Map<String, Object?>> data = [];

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final result = await DB.instance.users();

    if (mounted) {
      setState(() {
        data = result;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'مدیریت کاربران',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('کاربر جدید'),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              children: data.map((u) {
                return Card(
                  child: ListTile(
                    title: Text(
                      '${u['display_name']} (${u['username']})',
                    ),
                    subtitle: Text(
                      '${u['role'] == 'admin' ? 'مدیر' : 'اپراتور'}'
                      ' • ${u['active'] == 1 ? 'فعال' : 'غیرفعال'}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.edit,
                        color: blue,
                      ),
                      onPressed: () => edit(u),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> edit([
    Map<String, Object?>? u,
  ]) async {
    final name = TextEditingController(
      text: '${u?['display_name'] ?? ''}',
    );

    final user = TextEditingController(
      text: '${u?['username'] ?? ''}',
    );

    final pw = TextEditingController();

    String role = '${u?['role'] ?? 'operator'}';

    bool active = (u?['active'] ?? 1) == 1;

    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => StatefulBuilder(
        builder: (x, setD) => AlertDialog(
          title: Text(
            u == null ? 'کاربر جدید' : 'ویرایش کاربر',
          ),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'نام نمایشی',
                  ),
                ),
                TextField(
                  controller: user,
                  decoration: const InputDecoration(
                    labelText: 'نام کاربری',
                  ),
                ),
                TextField(
                  controller: pw,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: u == null
                        ? 'رمز عبور'
                        : 'رمز جدید (اختیاری)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  items: const [
                    DropdownMenuItem(
                      value: 'admin',
                      child: Text('مدیر'),
                    ),
                    DropdownMenuItem(
                      value: 'operator',
                      child: Text('اپراتور'),
                    ),
                  ],
                  onChanged: (v) {
                    setD(() => role = v ?? role);
                  },
                ),
                SwitchListTile(
                  value: active,
                  title: const Text('حساب فعال'),
                  onChanged: (v) {
                    setD(() => active = v);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(x, true),
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    if (yes == true) {
      try {
        await DB.instance.saveUser(
          id: u?['id'] as int?,
          username: user.text,
          name: name.text,
          password: pw.text,
          role: role,
          active: active,
        );

        await load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('خطا: $e'),
            ),
          );
        }
      }
    }

    name.dispose();
    user.dispose();
    pw.dispose();
  }
}
