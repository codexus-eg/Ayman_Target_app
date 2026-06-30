import 'package:ayman_target/app_colors.dart';
import 'package:ayman_target/constants.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();

  // ✨ المتغير الجديد الخاص بالفرع (القيمة الافتراضية بنها)
  String _selectedBranch = AppConstants.defaultBranch;
  bool _isLoading = false;

  void _register() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      UserCredential userCredential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      await userCredential.user!.sendEmailVerification();

      // ✨ حفظ الفرع المختار (branch) جوه بيانات الموظف مع الدمج (merge)
      await FirebaseFirestore.instance.collection('users').doc(userCredential.user!.uid).set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'role': 'employee',
        'branch': _selectedBranch, // 👈 حفظ الفرع هنا
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await FirebaseAuth.instance.signOut();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("تم إنشاء الحساب! برجاء مراجعة بريدك الإلكتروني لتفعيل الحساب أولاً قبل الدخول.", textAlign: TextAlign.center),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String message = "حدث خطأ ما";
      if (e.code == 'email-already-in-use') message = "هذا الإيميل مسجل بالفعل";
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        debugPrint('خطأ في التسجيل: $e');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("حدث خطأ أثناء التسجيل. حاول مرة أخرى.")));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("تسجيل حساب جديد")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              _buildField(_nameController, "الاسم بالكامل", Icons.person, (v) => v!.isEmpty ? "ادخل الاسم" : null),
              const SizedBox(height: 15),
              _buildField(_phoneController, "رقم الموبايل", Icons.phone, (v) {
                if (v == null || v.isEmpty) return "رقم الموبايل مطلوب";
                if (v.length != 11) return "رقم الموبايل يجب أن يتكون من 11 رقماً بالضبط";
                RegExp phoneRegex = RegExp(r'^(010|011|012|015)[0-9]{8}$');
                if (!phoneRegex.hasMatch(v)) return "رقم الموبايل يجب أن يبدأ بـ 010 أو 011 أو 012 أو 015";
                return null;
              }),
              const SizedBox(height: 15),

              // ✨ [إضافة جديدة]: قائمة اختيار الفرع للموظف الجديد
              DropdownButtonFormField<String>(
                initialValue: _selectedBranch,
                decoration: InputDecoration(
                  labelText: "اختر الفرع التابع له",
                  prefixIcon: const Icon(Icons.location_city),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                 items: AppConstants.branches.map((String branch) {
                  return DropdownMenuItem<String>(
                    value: branch,
                    child: Text(branch),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _selectedBranch = value);
                },
              ),

              const SizedBox(height: 15),
              _buildField(_emailController, "الإيميل", Icons.email, (v) {
                if (v == null || v.isEmpty) return "الإيميل مطلوب";
                if (!RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(v)) return "إيميل غير صحيح";
                return null;
              }),
              const SizedBox(height: 15),
              _buildField(_passwordController, "كلمة السر", Icons.lock, (v) => v!.length < 6 ? "كلمة السر ضعيفة" : null, isPass: true),
              const SizedBox(height: 30),
              _isLoading
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: _register,
                  child: const Text("إنشاء الحساب", style: TextStyle(color: Colors.white, fontSize: 18)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, String? Function(String?)? validator, {bool isPass = false}) {
    return TextFormField(
      controller: controller,
      obscureText: isPass,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        errorStyle: const TextStyle(color: Colors.red),
      ),
    );
  }
}