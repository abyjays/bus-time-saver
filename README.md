# Bus Time Saver 🚌

Bus Time Saver is a secure, efficient Flutter application designed to help users track, manage, and search for local bus routes, stops, and schedules. 

## ✨ Key Features (v1.2.0)

* **Comprehensive Route Management:** Save and edit detailed bus routes, including Start Location, Destination, specific **Bus Stops**, and **Bus Stands**.
* **Smart State-Filtered Search:** Autocomplete suggestions for locations are intelligently filtered based on the selected state, preventing irrelevant global search results.
* **Encrypted Local Storage:** All local data is strictly secured using **SQLCipher** (256-bit AES encryption) to ensure privacy and data integrity.
* **Robust Backup & Restore:** 
  * Export safe, plain-text backups to your local device storage.
  * Seamlessly import legacy or plain-text SQLite backups. The app automatically absorbs the data and securely re-encrypts it behind the scenes.
* **Automated Data Migrations:** The database utilizes automated schema migrations, ensuring that future app updates never break or corrupt your existing saved routes.
* **In-App OTA Updates:** Powered by GitHub Releases, the app automatically notifies you when a new version is available and securely installs it over the air without requiring the Google Play Store.

## 🚀 Installation (For Users)

1. Navigate to the [Releases](../../releases) tab on this GitHub repository.
2. Download the latest `app-release.apk` (Version 1.2.0 or higher).
3. Open the APK on your Android device to install. 
4. *Note: Future updates will be handled automatically inside the app!*

## 🛠️ Build Instructions (For Developers)

If you want to clone and compile this project yourself, you must configure your own Android Keystore, as the production keystore is intentionally excluded from this repository for security.

1. **Clone the repository:**
   ```bash
   git clone [https://github.com/your-username/bus_time_saver.git](https://github.com/your-username/bus_time_saver.git)
   cd bus_time_saver
