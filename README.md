# TPS Görsel Sınav Sistemi — Supabase & X-Ray Simülasyonu v2.0

Bu proje, X-Ray güvenlik tarama sınavı ve eğitim süreçlerini simüle etmek için hazırlanmış **profesyonel web uygulamasıdır**.

## Özellikler

### 🛡️ Sınav Motoru & X-Ray İşleme
- **7 Gerçek X-Ray Filtre Modu**:
  - `NORM`: Standart renkli X-Ray görüntüsü (Organik, İnorganik, Karışık).
  - `NEG`: Negatif / Ters Çevirme (Kısayol: `G`).
  - `B&W`: Siyah-Beyaz Monokrom Vurgulama (Kısayol: `W`).
  - `SEN`: Süper Yoğunluk / Yüksek Kontrast Boost (Kısayol: `S`).
  - `HI`: Yüksek Organik Emilim Vurgusu (Kısayol: `H`).
  - `O₂`: Sadece Organik Malzeme (Turuncu/Kahve boost) (Kısayol: `O`).
  - `OS`: Organik Sıyırma / Metal-İnorganik Ayırımı (Kısayol: `P`).
- **Görüntü Yakınlaştırma & Sürükleme (Pan/Zoom)**:
  - Fare tekerleği (`wheel`) ile doğrudan yakınlaştırma/uzaklaştırma.
  - Fare ile basılı tutup sürükleyerek görüntü kaydırma (Pan).
  - Ekran kontrol butonları ile hassas yön ve ölçek kontrolü.
  - Tek tuşla görünüm ve mod sıfırlama (`R`).
- **Hassas Alan İşaretleme & Koruma**:
  - X-Ray üzerinde şüpheli/tehdit materyali daire ile işaretleme.
  - Yüzdelik (`%`) bazlı bağıl konumlandırma sayesinde ekran boyutu ve zoom değişse dahi işaretçinin yeri bozulmaz.
  - Sorular arasında geçiş yapıldığında önceki işaretleme ve seçilen cevabın otomatik geri yüklenmesi.
- **Sağ Panel 25s Soru Süresi & Genel Sınav Sayacı**:
  - **Soru Süresi**: Her soru için sağ panelde ve görüntü altında renk değiştiren 25 saniyelik dijital geri sayım barı ve sayacı (10s turuncu, 5s kırmızı uyarısı). Süre bitince karartma overlay'i açılır.
  - **Sınav Süresi**: Toplam 20 dakikalık (1200s) sınav geri sayımı.
- **Klavye Kısayol Desteği**:
  - `1 - 5` veya `A - E`: Seçenek belirleme.
  - `← / →` Sol / Sağ Yön Tuşları: Sorular arası geçiş.
  - `N, G, W, S, H, O, P`: Anlık filtre modları.
  - `R`: Sıfırlama.

---

### 📊 Sınav Sonu Raporu & Yanlış Cevap İnceleme ("Yanlışlarını Gör")
- **100 Üzerinden Puanlama**: 50 soru üzerinden hesaplanan net puan, Doğru, Yanlış ve Boş bırakılan soru istatistikleri.
- **Yanlış Cevap İnceleme Paneli**:
  - Personnel sınavı bitirdiğinde yapılan tüm yanlış ve boş sorular X-Ray görsel önizlemesiyle birlikte listelenir.
  - Kendi seçtiği yanlış şık ❌ kırmızı renkle, sorunun doğru şıkkı ✅ yeşil renkle açıkça gösterilir.
- **Sınavdan Çıkış**: `🚪 Sınavdan Çıkış Yap ve Kapat` butonu ile sınav oturumu tamamlanır ve giriş ekranına dönülür.

---

### 👑 Yönetici Paneli (3 Sekmeli Admin)
1. **Soru Yönetimi**:
   - Yeni X-Ray sorusu ekleme (Soru metni, Supabase Storage'a X-Ray resmi yükleme, 5 şık A-E, doğru cevap seçimi, zorluk seviyesi 1-4).
   - Ekli soruların listesi, resim önizlemesi ve soru silme işlemi.
2. **Personel Yönetimi**:
   - Yeni personel hesabı tanımlama (Sicil No, Ad Soyad, Havalimanı/İstasyon, Vardiya, Şifre).
   - Kayıtlı personel listesini görüntüleme.
3. **Sınav Sonuçları & Analiz**:
   - Katılım sayısı, başarı oranı (%), ortalama puan ve başarılı personel istatistik kartları.
   - Detaylı personel bazlı sınav sonuç tablosu.
   - **CSV İndir**: Sınav performans raporunu tek tıkla Excel/CSV formatında indirme.

---

## Kurulum ve Çalıştırma

1. **Supabase Kurulumu**:
   - Supabase panelinde SQL Editor kısmına gelin.
   - `supabase.sql` dosyasının içeriğini kopyalayıp **Run** düğmesine basarak çalıştırın.
2. **Yapılandırma (`config.js`)**:
   - `config.js` dosyasını açıp Supabase URL ve anon key bilgilerinizi tanımlayın:
     ```javascript
     window.SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
     window.SUPABASE_ANON_KEY = 'YOUR-ANON-KEY';
     ```
3. **Uygulamayı Çalıştırma**:
   - `index.html` dosyasını bir web sunucusunda veya doğrudan tarayıcıda çalıştırın.
4. **Demo Personel Girişi**:
   - Sicil No: `DEMO001`
   - Şifre: `1234`
5. **Yönetici Girişi**:
   - Supabase Authentication > Users bölümünden email/password hesabı oluşturun.
   - Oluşan UUID değerini `admins` tablosuna ekleyin:
     ```sql
     insert into admins(auth_user_id) values('YOUR-AUTH-USER-UUID');
     ```
