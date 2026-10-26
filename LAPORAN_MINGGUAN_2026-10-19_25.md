Saifudin Juhri || UBIG
Laporan Mingguan : 19 Oktober – 25 Oktober 2026

NoBox.Ai - Chat Mobile App (Flutter)

=> Mengimplementasikan **core providers, services, dan UI screens** utama (ChatProvider, SignalRService, PushNotificationService, AuthProvider, ChatSettingsProvider) serta integrasi **Firebase & Background Service** native Android untuk fondasi arsitektur aplikasi yang scalable. ✅

=> Memperbaiki **ANR / Not Responding** secara menyeluruh: memindahkan operasi blocking SignalR ke **worker thread** di native Android (SignalRBackgroundService.kt), menambahkan **timeout & exponential backoff**, menghapus delay paksa 5 detik di Splash Screen, mengoptimalkan lifecycle resume dengan `postFrameCallback`, serta mematikan `debugPrint` payload besar di mode release. ✅

=> Mengoptimalkan **performa Chat Detail ListView**: mengganti `shrinkWrap: true` dengan virtualisasi penuh (`shrinkWrap: false`, `cacheExtent: 1000`, `RepaintBoundary`), menambahkan **cached `_displayMessages`** dengan hash-based invalidation, serta **O(1) index lookup** via map — menghilangkan frame drop saat scroll & histori panjang. ✅

=> Memperbaiki **deduplikasi pesan real-time** (double bubble) dengan algoritma pencocokan **content + tipe media + toleransi waktu 2–5 detik** + fallback substring, serta guard anti-duplikat untuk pesan lokal (ID kosong/temp_). ✅

=> Menambahkan **termination cleanup** saat app di-kill (swipe recent): force-stop background service, cancel polling timer, disconnect SignalR eksplisit, clear current room — memastikan notifikasi tetap jalan di launch berikutnya. ✅

=> Mengimplementasikan **debounced notifyListeners** (~16ms) di ChatProvider + guard `_isRefreshingFirstPage` untuk mencegah UI freeze saat event SignalR datang bersamaan (message burst). ✅

=> Mengoptimalkan **SharedPreferences write storm**: menambahkan **debounce 400–600ms** untuk semua write (pinned, archived, read, starred, cache pesan) serta membatasi cache pesan lokal maksimal **50 item terakhir**. ✅

=> Memperbaiki **notifikasi click → app restart**: mengganti `FLAG_ACTIVITY_CLEAR_TASK` dengan `SINGLE_TOP` + handling `onNewIntent` di MainActivity, sehingga klik notifikasi buka chat langsung tanpa reload splash/login. ✅

=> Menyempurnakan **ContactInfoPage & Contact Info Screen**: manajemen metadata chat, profile detail, dan integrasi dengan ChatProvider untuk state yang konsisten. ✅

=> Membangun **Archive List Page** dengan pagination, filter, dan UI yang konsisten dengan ChatListPage. ✅

=> Merapikan **ChatListPage**: perbaikan filter advanced (Mute AI, Channel, ChatType, ReadStatus, Link, Funnel, Tag, HumanAgent), search dengan debounce 300ms, dan empty state interaktif "Kontak tidak ditemukan". ✅

=> Update **MessageBubbleWidget**: perbaikan layout reply message, sticker detection (.webm, .mp4, .mov, .tgs, .webp), serta render timestamp yang presisi. ✅

=> Memperbaiki **SignalRService**: parsing JWT pakai `compute()` (background isolate), debug logging tipe pesan non-teks, serta handling event `TerimaPesan` yang lebih robust. ✅

=> Update **Splash Screen**: inisialisasi async paralel dengan **timeout 3 detik** (bawah threshold ANR 5s), navigasi immediate, SignalR deferred ke `postFrameCallback`. ✅

=> Hasil `flutter analyze`: **0 error**, 97 warning (non-fatal: deprecation `withOpacity`, unused imports/variables, dead code). ✅

=> Dokumentasi teknis lengkap: **Laporan Analisis ANR**, **Ringkasan Perbaikan**, **Checklist Validasi Manual**, serta **Rencana Hardening** (isolate parsing, cache persist, bersihkan dead code). ✅

NoBox Chat Mobile App
=> Eksplorasi integrasi **TokenGateway AI (DeepSeek v4 Pro / Qwen3 Coder)** via skill `tokengateway-agent` untuk code review, refactor, dan generate boilerplate — sudah siap pakai via CLI atau chat. ✅

=> Identifikasi **4 risiko performa non-ANR** untuk HP low-end: parsing JSON di main isolate (arsip/cache), decode JSON berulang tiap polling 60s, `context.watch` di level halaman, linear scan pencocokan pesan — sudah direncanakan perbaikan minggu depan. 🔄

Link Repo: https://github.com/UBIG/NoBox_Chat (branch main, latest commit 5ca0803)