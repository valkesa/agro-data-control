import 'package:firebase_auth/firebase_auth.dart';

class FirebaseEmailAuthService {
  const FirebaseEmailAuthService();

  Stream<User?> authStateChanges() => FirebaseAuth.instance.authStateChanges();

  User? get currentUser => FirebaseAuth.instance.currentUser;

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  Future<UserCredential> signInWithGoogle() {
    final GoogleAuthProvider provider = GoogleAuthProvider();
    return FirebaseAuth.instance.signInWithPopup(provider);
  }

  Future<void> updatePassword({required String newPassword}) {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'No hay un usuario autenticado.',
      );
    }
    return user.updatePassword(newPassword);
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();
}
