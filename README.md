# GoogleTV Tools for iOS

Bagimsiz, deneysel ve acik kaynak bir Google TV yonetim uygulamasi. Tellyscope'un resmi iOS surumu degildir. Orijinal proje: https://github.com/man15h/tellyscope

## Ozellikler
- Google TV'ye ADB TCP ile baglanti (varsayilan 5555 portu)
- TV kumandasi: yonler, OK, geri, ana ekran, ses
- Yuklu uygulamalari listeleme, acma, devre disi birakma ve etkinlestirme
- Android surumu ve depolama bilgisi

## Sinirlamalar
- Android 11+ 6 haneli **Wireless Debugging pairing / TLS** henuz yoktur.
- Cihazda klasik ag ADB etkin degilse baglanti kurulamiyor.
- Gercek iPhone ve Google TV uzerinde henuz test edilmedi.
- Sistem paketlerini kapatmak TV'yi bozabilir.
- GitHub Actions'in urettigi IPA **imzasizdir** ve dogrudan normal iPhone'a yuklenemez.

## Build
Actions > Build iOS IPA > Run workflow.

Workflow macOS, XcodeGen, Xcode ve Swift Package Manager kullanarak iphoneos icin imzasiz IPA olusturur. Sonucu Actions sayfasindaki Artifacts bolumunden indirin. iPhone'a yuklemek icin ayrica uygun kod imzalama gerekir.

## Lisans
Bu bagimsiz proje GPL-3.0-or-later kosullariyla paylasilir. Kaynak kod orijinal Tellyscope'tan kopyalanmamistir.

## Yeni uygulama yönetimi (deneysel)
- Dosyalar uygulamasindan APK secimi ve ADB sync ile /data/local/tmp uzerinden yukleme
- pm install -r ile kurulum; aktarim sonrasi gecici APK silme
- Uygulama kaldirma (kullanici 0), durdurma, veri silme ve uygulama ayarlari
- Android runtime izinlerini pm grant / pm revoke ile degistirme (izin uygunsa)
- TV'de sistem, Wi-Fi, uygulama, gelistirici ve erisilebilirlik ayar sayfalarini acma
- Elle ADB shell komutu gonderme

Bu islemler yalnizca TV'ye yetkili klasik ADB baglantisi kurulduktan sonra calisir. Android 11+ 6 haneli TLS pairing protokolu **henuz uygulanmadi**. Bir uygulamanin ayarlar sayfasini acmak, ayarlari iPhone'da dogrudan degistirmek anlamina gelmez. Yaptiginiz degisiklikler kendi sorumlulugunuzdadir. Dosya aktarimi ve tum komutlar gercek TV'de henuz dogrulanmadi.
