import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

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

String passHash(String s) =>
    sha256.convert(utf8.encode(s)).toString();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows ||
      Platform.isLinux ||
      Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
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
        ? (Platform.environment['APPDATA'] ??
            Directory.current.path)
        : Directory.current.path;

    final dir = Directory(
      p.join(base, 'EngineTestManagerPro'),
    );

    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    db = await databaseFactory.openDatabase(
      p.join(dir.path, 'engine_manager.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (d, v) async {
          await d.execute(
            'CREATE TABLE users('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'username TEXT UNIQUE NOT NULL,'
            'password_hash TEXT NOT NULL,'
            'display_name TEXT NOT NULL,'
            'role TEXT NOT NULL,'
            'active INTEGER NOT NULL DEFAULT 1)',
          );

          await d.execute(
            'CREATE TABLE shifts('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'document_no TEXT NOT NULL,'
            'shift_date TEXT NOT NULL,'
            'operator_name TEXT NOT NULL,'
            'status TEXT NOT NULL DEFAULT "باز",'
            'created_at TEXT NOT NULL)',
          );

          await d.execute(
            'CREATE TABLE engines('
            'id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'shift_id INTEGER NOT NULL,'
            'row_no INTEGER NOT NULL,'
            'engine_no TEXT NOT NULL,'
            'result TEXT NOT NULL,'
            'errors TEXT NOT NULL,'
            'notes TEXT NOT NULL,'
            'created_at TEXT NOT NULL)',
          );

          await d.insert('users', {
            'username': 'admin',
            'password_hash': passHash('admin123'),
            'display_name': 'مدیر سیستم',
            'role': 'admin',
            'active': 1,
          });
        },
        onUpgrade: (d, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await d.execute(
              'CREATE TABLE IF NOT EXISTS users('
              'id INTEGER PRIMARY KEY AUTOINCREMENT,'
              'username TEXT UNIQUE NOT NULL,'
              'password_hash TEXT NOT NULL,'
              'display_name TEXT NOT NULL,'
              'role TEXT NOT NULL,'
              'active INTEGER NOT NULL DEFAULT 1)',
            );

            await d.execute(
              'CREATE TABLE IF NOT EXISTS shifts('
              'id INTEGER PRIMARY KEY AUTOINCREMENT,'
              'document_no TEXT NOT NULL,'
              'shift_date TEXT NOT NULL,'
              'operator_name TEXT NOT NULL,'
              'status TEXT NOT NULL DEFAULT "باز",'
              'created_at TEXT NOT NULL)',
            );

            await d.execute(
              'CREATE TABLE IF NOT EXISTS engines('
              'id INTEGER PRIMARY KEY AUTOINCREMENT,'
              'shift_id INTEGER NOT NULL,'
              'row_no INTEGER NOT NULL,'
              'engine_no TEXT NOT NULL,'
              'result TEXT NOT NULL,'
              'errors TEXT NOT NULL,'
              'notes TEXT NOT NULL,'
              'created_at TEXT NOT NULL)',
            );
          }
        },
      ),
    );
  }

  Future<Map<String, Object?>?> login(
    String u,
    String pw,
  ) async {
    final a = await db!.query(
      'users',
      where: 'username=? AND active=1',
      whereArgs: [u.trim()],
      limit: 1,
    );

    if (a.isEmpty ||
        a.first['password_hash'] != passHash(pw)) {
      return null;
    }

    return a.first;
  }

  Future<List<Map<String, Object?>>> shifts() =>
      db!.query('shifts', orderBy: 'id DESC');

  Future<List<Map<String, Object?>>> engines(int id) =>
      db!.query(
        'engines',
        where: 'shift_id=?',
        whereArgs: [id],
        orderBy: 'row_no',
      );

  Future<int> createShift(
    String doc,
    String date,
    String op,
  ) =>
      db!.insert('shifts', {
        'document_no': doc,
        'shift_date': date,
        'operator_name': op,
        'status': 'باز',
        'created_at': nowStamp(),
      });

  Future<void> closeShift(int id) async {
    await db!.update(
      'shifts',
      {'status': 'بسته'},
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<int> add(Map<String, Object?> m) =>
      db!.insert('engines', m);

  Future<void> update(
    int id,
    Map<String, Object?> m,
  ) async {
    await db!.update(
      'engines',
      m,
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> delete(int id) async {
    await db!.delete(
      'engines',
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> users() =>
      db!.query('users', orderBy: 'id');

  Future<void> saveUser({
    int? id,
    required String username,
    required String name,
    required String password,
    required String role,
    required bool active,
  }) async {
    final m = <String, Object?>{
      'username': username.trim(),
      'display_name': name.trim(),
      'role': role,
      'active': active ? 1 : 0,
    };

    if (password.isNotEmpty) {
      m['password_hash'] = passHash(password);
    }

    if (id == null) {
      if (password.isEmpty) {
        throw Exception('رمز عبور الزامی است');
      }

      await db!.insert('users', m);
    } else {
      await db!.update(
        'users',
        m,
        where: 'id=?',
        whereArgs: [id],
      );
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
        fontFamily: 'Segoe UI',
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
          textDirection: TextDirection.rtl,
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
  final u = TextEditingController(text: 'admin');
  final pw = TextEditingController();

  String error = '';

  Future<void> go() async {
    final x = await DB.instance.login(u.text, pw.text);

    if (x == null) {
      setState(() {
        error = 'نام کاربری یا رمز اشتباه است';
      });
    } else {
      widget.onLogin(x);
    }
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
              color: gold.withOpacity(.4),
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
                'PRO 2.1',
                style: TextStyle(
                  color: gold,
                  letterSpacing: 4,
                ),
              ),
              const SizedBox(height: 25),
              TextField(
                controller: u,
                decoration: const InputDecoration(
                  labelText: 'نام کاربری',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pw,
                obscureText: true,
                onSubmitted: (_) => go(),
                decoration: const InputDecoration(
                  labelText: 'رمز عبور',
                ),
              ),
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
              const Text(
                'ورود اولیه: admin / admin123',
                style: TextStyle(
                  color: muted,
                  fontSize: 11,
                ),
              ),
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
    shifts = await DB.instance.shifts();

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext c) {
    final pages = <Widget>[
      Dashboard(
        shifts: shifts,
        refresh: load,
        open: open,
      ),
      Archive(
        shifts: shifts,
        open: open,
      ),
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
                nav(1, Icons.archive, 'فایل‌های ذخیره‌شده'),
                if (admin)
                  nav(
                    2,
                    Icons.manage_accounts,
                    'مدیریت کاربران',
                  ),
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
      selectedTileColor: gold.withOpacity(.13),
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
        builder: (_) => ShiftPage(shift: s),
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

  const Dashboard({
    super.key,
    required this.shifts,
    required this.refresh,
    required this.open,
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
                onPressed: () => create(c, refresh, open),
                icon: const Icon(Icons.add),
                label: const Text('شروع شیفت جدید'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Wrap(
            spacing: 12,
            children: [
              stat('کل فرم‌ها', shifts.length, gold),
              stat('شیفت باز', op, green),
              stat('شیفت بسته', shifts.length - op, blue),
            ],
          ),
          const SizedBox(height: 22),
          const Text(
            'آخرین شیفت‌ها',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
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
    BuildContext c,
    VoidCallback refresh,
    ValueChanged<Map<String, Object?>> open,
  ) async {
    final doc = TextEditingController(
      text: 'ET-${DateTime.now().millisecondsSinceEpoch % 1000000}',
    );

    final date = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()),
    );

    final op = TextEditingController();

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
              TextField(
                controller: op,
                decoration: const InputDecoration(
                  labelText: 'نام اپراتور',
                ),
              ),
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

    if (ok != true ||
        doc.text.trim().isEmpty ||
        op.text.trim().isEmpty) {
      return;
    }

    final id = await DB.instance.createShift(
      doc.text,
      date.text,
      op.text,
    );

    refresh();

    final s = (await DB.instance.shifts()).firstWhere(
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

// ================= SHIFT PAGE =================

class ShiftPage extends StatefulWidget {
  final Map<String, Object?> shift;

  const ShiftPage({
    super.key,
    required this.shift,
  });

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  List<Map<String, Object?>> rows = [];

  String q = '';

  bool get closed => widget.shift['status'] == 'بسته';

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows = await DB.instance.engines(
      widget.shift['id'] as int,
    );

    if (mounted) {
      setState(() {});
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
          if (!closed)
            TextButton.icon(
              onPressed: closeShift,
              icon: const Icon(Icons.lock),
              label: const Text('بستن شیفت'),
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
                  FilledButton.icon(
                    onPressed: rows.length >= 80
                        ? null
                        : () => edit(),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('ثبت / اسکن موتور'),
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
          backgroundColor: gold.withOpacity(.15),
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
          '${r['result']} • ${r['errors']}',
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
  }) async {
    final no = TextEditingController(
      text: '${row?['engine_no'] ?? ''}',
    );

    final err = TextEditingController(
      text: '${row?['errors'] ?? ''}',
    );

    final notes = TextEditingController(
      text: '${row?['notes'] ?? ''}',
    );

    String result = '${row?['result'] ?? 'در انتظار'}';

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
                  value: result,
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
                    setD(() => result = v ?? result);
                  },
                ),
                TextField(
                  controller: err,
                  decoration: const InputDecoration(
                    labelText: 'نوع ایراد',
                  ),
                ),
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
                Navigator.pop(x, {
                  'engine_no': no.text.trim(),
                  'result': result,
                  'errors': err.text.trim(),
                  'notes': notes.text.trim(),
                });
              },
              child: const Text('ذخیره'),
            ),
          ],
        ),
      ),
    );

    if (d == null || '${d['engine_no']}'.isEmpty) {
      return;
    }

    final duplicate = rows.any(
      (r) =>
          r['engine_no'] == d['engine_no'] &&
          r['id'] != row?['id'],
    );

    if (duplicate) {
      final yes = await showDialog<bool>(
        context: context,
        builder: (x) => AlertDialog(
          title: const Text('شماره تکراری'),
          content: const Text(
            'این شماره قبلاً در همین فرم ثبت شده؛ تست مجدد ثبت شود؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(x, false),
              child: const Text('لغو'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(x, true),
              child: const Text('ثبت مجدد'),
            ),
          ],
        ),
      );

      if (yes != true) return;
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
    };

    if (row == null) {
      await DB.instance.add(m);
    } else {
      await DB.instance.update(
        row['id'] as int,
        m,
      );
    }

    await load();
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
      await DB.instance.delete(r['id'] as int);
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

    if (yes == true &&
        n != null &&
        n > 0 &&
        n <= 80 &&
        !rows.any(
          (e) => e['row_no'] == n && e['id'] != r['id'],
        )) {
      await DB.instance.update(
        r['id'] as int,
        {...r, 'row_no': n},
      );

      await load();
    }
  }

  Future<void> closeShift() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (x) => AlertDialog(
        title: const Text('بستن شیفت'),
        content: const Text(
          'پس از بستن، فرم فقط قابل مشاهده خواهد بود.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(x, false),
            child: const Text('لغو'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(x, true),
            child: const Text('بستن'),
          ),
        ],
      ),
    );

    if (yes == true) {
      await DB.instance.closeShift(
        widget.shift['id'] as int,
      );

      if (mounted) {
        Navigator.pop(context);
      }
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
    data = await DB.instance.users();

    if (mounted) {
      setState(() {});
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
                  value: role,
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
  }
}
