# Bus Time Saver 🚌

Bus Time Saver is a modern, privacy-first Flutter application designed to track, filter, and manage bus schedules efficiently. Built with an emphasis on local security and an optimized Material 3 user interface, the app ensures that your data stays strictly on your device—fully encrypted at rest.

---

## ✨ Features

- **Modern UI/UX**: Fully integrated **Material 3** design system with a seamless **native splash screen** (via `flutter_native_splash`).
- **Interactive Home Screen**: Advanced search and horizontal filter chips (`All`, `Destination`, `Time`) enable lightning-fast data querying.
- **Real-Time State Refreshes**: Employs optimized `UniqueKey` implementations within the widget tree to instantly reflect database modifications on the UI.
- **Smart Autocomplete**: The "Add Bus" screen automatically learns from your history, providing contextual suggestions for bus names, origins, and destinations.

---

## 🔒 Enterprise-Grade Security

Privacy and data integrity are the core pillars of Bus Time Saver. The app implements multi-layered security protocols to guarantee your information is safe from interception, corruption, or leakage:

1. **AES-256 Database Encryption**: The local SQLite database is powered by `sqflite_sqlcipher`. The database is encrypted at rest using a 256-bit cryptographic key safely stored in the device's hardware keystore via `flutter_secure_storage`.
2. **Pre-Restore Integrity Checks**: Backup `.db` files undergo strict, sandboxed pre-restore validations (including `PRAGMA integrity_check` and schema verification) to prevent malicious or corrupted files from overwriting the live database.
3. **Strict SQL Parameterization**: 100% of the app's database queries utilize parameterized arguments (`?`), completely neutralizing any risk of SQL injection attacks.
4. **Form Sanitization**: All user inputs undergo rigorous RegEx-based sanitization and trimming before saving.
5. **Production Logging Safeguards**: Sensitive runtime data and file paths are heavily guarded using Flutter's `kDebugMode` wrappers, ensuring that **zero sensitive data** ever leaks into `adb logcat` or standard outputs in release builds.

---

## 🛠 Tech Stack

<div style="display: flex; gap: 10px;">
  <img src="https://img.shields.io/badge/Flutter-%2302569B.svg?style=for-the-badge&logo=Flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Dart-%230175C2.svg?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/sqlite-%2307405e.svg?style=for-the-badge&logo=sqlite&logoColor=white" alt="SQLite">
</div>

* **UI Framework**: Flutter (Material 3)
* **Language**: Dart
* **Database**: SQLite (SQLCipher)
* **Key Storage**: Android Keystore / iOS Keychain

---

## 📖 About

Bus Time Saver was developed to provide users with a robust, offline-first tool to manage commuting schedules without compromising on personal data privacy. 

This project is actively maintained and its development lineage focuses heavily on best-practice application architecture and on-device security.

**Explore the Codebase & Contribute:**  
[GitHub Repository: bus_time_saver](https://github.com/YOUR_USERNAME/bus_time_saver)
