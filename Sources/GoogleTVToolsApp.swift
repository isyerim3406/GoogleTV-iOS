import SwiftUI
import UniformTypeIdentifiers

@main
struct GoogleTVToolsApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct ContentView: View {
    @AppStorage("tvAddress") private var address = "192.168.1.100"
    @AppStorage("tvPort") private var port = "5555"
    @State private var client: ADBClient?
    @State private var connected = false
    @State private var busy = false
    @State private var status = "Google TV IP adresini girin."
    @State private var output = ""
    @State private var packages: [String] = []
    @State private var query = ""
    @State private var showSystem = false
    @State private var deviceName = ""
    @State private var apkPicker = false
    @State private var installStatus = ""
    @State private var terminalCommand = ""
    @State private var selectedPackage = ""
    @State private var permission = ""
    @State private var allowPermission = true
    @State private var pendingCommand = ""
    @State private var pendingTitle = ""
    @State private var showConfirmation = false

    private var visiblePackages: [String] {
        packages.filter {
            (showSystem || !$0.hasPrefix("com.android.")) &&
            (query.isEmpty || $0.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
        TabView {
            NavigationStack {
                Form {
                Section("Google TV bağlantısı") {
                    TextField("IP adresi", text: $address)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.numbersAndPunctuation)
                    TextField("ADB portu", text: $port).keyboardType(.numberPad)
                    Button(connected ? "Bağlantıyı kes" : "TV'ye bağlan") {
                        if connected {
                            client?.close(); client = nil; connected = false
                            status = "Bağlantı kesildi."
                        } else { connect() }
                    }.disabled(busy)
                    Text(status).font(.footnote)
                    if !deviceName.isEmpty { Text(deviceName).font(.footnote) }
                }
                if connected {
                    Section("Cihaz bilgileri") {
                        Button("Depolama") { run("df -h /data") }
                        Button("Android sürümü") { run("getprop ro.build.version.release") }
                        Button("TV'yi yeniden başlat") { ask("TV yeniden başlatılsın mı?", "reboot") }
                    }
                }
                    if !output.isEmpty {
                        Section("Son işlem") { Text(output).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Bağlantı")
            }
            .tabItem { Label("Bağlantı", systemImage: "wifi") }

            NavigationStack {
                Form {
                    if connected {
                    Section("Kumanda") {
                        HStack { Spacer(); key("↑", 19); Spacer() }
                        HStack { Spacer(); key("←", 21); key("OK", 23); key("→", 22); Spacer() }
                        HStack { Spacer(); key("↓", 20); Spacer() }
                        HStack { key("Geri", 4); key("Ana ekran", 3); key("Menü", 82) }
                        HStack { key("Ses −", 25); key("Sessiz", 164); key("Ses +", 24) }
                    }
                    } else { Text("Önce TV'ye bağlanın.").foregroundStyle(.secondary) }

                    if !output.isEmpty {
                        Section("Son işlem") { Text(output).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Kumanda")
            }
            .tabItem { Label("Kumanda", systemImage: "remote.fill") }

            NavigationStack {
                Form {
                    if connected {
                    Section("Uygulamalar") {
                        Button("Yüklü uygulamaları listele") { run("pm list packages", list: true) }
                        Toggle("Sistem paketlerini göster", isOn: $showSystem)
                        TextField("Paket ara", text: $query)
                            .textInputAutocapitalization(.never)
                        ForEach(visiblePackages, id: \.self) { package in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(package).font(.caption).textSelection(.enabled)
                                HStack {
                                    Button("Aç") {
                                        run("monkey -p \(package) -c android.intent.category.LAUNCHER 1")
                                    }
                                    Button("Devre dışı") { run("pm disable-user --user 0 \(package)") }
                                    Button("Etkinleştir") { run("pm enable \(package)") }
                                }.buttonStyle(.bordered).font(.caption)
                                HStack {
                                    Button("Ayarlar") { run("am start -a android.settings.APPLICATION_DETAILS_SETTINGS -d package:\(package)") }
                                    Button("Durdur") { run("am force-stop \(package)") }
                                    Button("İzinler") {
                                        selectedPackage = package
                                        run("dumpsys package \(package)")
                                    }
                                }.buttonStyle(.bordered).font(.caption)
                                HStack {
                                    Button("Verileri sil", role: .destructive) {
                                        ask("Veriler silinsin mi?", "pm clear \(package)")
                                    }
                                    Button("Kaldır", role: .destructive) {
                                        ask("Uygulama kaldırılsın mı?", "pm uninstall --user 0 \(package)")
                                    }
                                }.buttonStyle(.bordered).font(.caption)
                            }
                        }
                    }
                    } else { Text("Önce TV'ye bağlanın.").foregroundStyle(.secondary) }

                    if !output.isEmpty {
                        Section("Son işlem") { Text(output).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Uygulamalar")
            }
            .tabItem { Label("Uygulamalar", systemImage: "square.grid.2x2.fill") }

            NavigationStack {
                Form {
                    if connected {
                    Section("APK yükleme") {
                        Button("iPhone'dan APK seç ve yükle") { apkPicker = true }
                        Text(installStatus).font(.caption)
                    }
                    Section("TV ayarlarını aç") {
                        Button("Genel ayarlar") { run("am start -a android.settings.SETTINGS") }
                        Button("Wi-Fi") { run("am start -a android.settings.WIFI_SETTINGS") }
                        Button("Uygulama ayarları") { run("am start -a android.settings.MANAGE_APPLICATIONS_SETTINGS") }
                        Button("Geliştirici ayarları") { run("am start -a android.settings.APPLICATION_DEVELOPMENT_SETTINGS") }
                        Button("Erişilebilirlik") { run("am start -a android.settings.ACCESSIBILITY_SETTINGS") }
                    }
                    Section("Uygulama izinleri") {
                        TextField("Paket", text: $selectedPackage).textInputAutocapitalization(.never)
                        TextField("Örn. android.permission.CAMERA", text: $permission).textInputAutocapitalization(.never)
                        Toggle("İzni ver", isOn: $allowPermission)
                        Button("İzni uygula") {
                            if safeName(selectedPackage) && safeName(permission) {
                                ask("İzin değiştirilsin mi?", "pm \(allowPermission ? "grant" : "revoke") \(selectedPackage) \(permission)")
                            } else { output = "Geçersiz paket veya izin adı." }
                        }
                    }
                    Section("ADB terminal") {
                        TextField("ADB shell komutu", text: $terminalCommand)
                        Button("Komutu gönder") {
                            if !terminalCommand.isEmpty { ask("Komut çalıştırılsın mı?", terminalCommand) }
                        }
                    }
                    } else { Text("Önce TV'ye bağlanın.").foregroundStyle(.secondary) }

                    if !output.isEmpty {
                        Section("Son işlem") { Text(output).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .navigationTitle("Araçlar")
            }
            .tabItem { Label("Araçlar", systemImage: "wrench.and.screwdriver.fill") }

        }
        .tint(.indigo)
        .fileImporter(isPresented: $apkPicker, allowedContentTypes: [UTType(filenameExtension: "apk") ?? .data]) { result in
            switch result {
            case .success(let url): installAPK(url)
            case .failure(let error): output = error.localizedDescription
            }
        }
        .alert(pendingTitle, isPresented: $showConfirmation) {
            Button("Onayla", role: .destructive) { run(pendingCommand) }
            Button("İptal", role: .cancel) {}
        } message: { Text(pendingCommand) }
        .overlay {
            if busy {
                ProgressView("İşleniyor…").padding(24).background(.regularMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
        }
    }
    private func safeName(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_.]+$", options: .regularExpression) != nil &&
        value.contains(".")
    }
    private func ask(_ title: String, _ command: String) {
        pendingTitle = title
        pendingCommand = command
        showConfirmation = true
    }
    private func installAPK(_ url: URL) {
        guard let c = client else { return }
        busy = true
        installStatus = "Aktarılıyor…"
        DispatchQueue.global(qos: .userInitiated).async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let path = "/data/local/tmp/" + UUID().uuidString + ".apk"
            do {
                let count = try c.pushFile(url, remotePath: path)
                DispatchQueue.main.async { installStatus = "\(count) bayt aktarıldı, kuruluyor…" }
                let result = try c.shell("pm install -r " + path)
                _ = try? c.shell("rm -f " + path)
                DispatchQueue.main.async {
                    output = result
                    installStatus = result.contains("Success") ? "Kurulum başarılı" : "Kurulum sonucunu kontrol edin"
                    busy = false
                }
            } catch {
                _ = try? c.shell("rm -f " + path)
                DispatchQueue.main.async {
                    output = error.localizedDescription
                    installStatus = "APK yüklenemedi"
                    busy = false
                }
            }
        }
    }
    private func key(_ title: String, _ code: Int) -> some View {
        Button(title) { run("input keyevent \(code)") }
            .buttonStyle(.bordered).disabled(busy)
    }
    private func connect() {
        busy = true
        status = "TV ekranındaki ADB iznini onaylayın…"
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = UInt16(port) ?? 5555
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let c = try ADBClient()
                try c.connect(host: host, port: p)
                let model = (try? c.shell("getprop ro.product.model"))?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                DispatchQueue.main.async {
                    client = c; connected = true; busy = false
                    deviceName = model; status = "Bağlandı"
                }
            } catch {
                DispatchQueue.main.async {
                    busy = false; connected = false
                    status = "Hata: \(error.localizedDescription)"
                }
            }
        }
    }
    private func run(_ command: String, list: Bool = false) {
        guard let c = client else { return }
        busy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let response = try c.shell(command)
                DispatchQueue.main.async {
                    if list {
                        packages = response.components(separatedBy: .newlines)
                            .filter { $0.hasPrefix("package:") }
                            .map { String($0.dropFirst(8)) }
                            .filter { $0.range(of: "^[A-Za-z0-9._]+$", options: .regularExpression) != nil }
                            .sorted()
                        output = "\(packages.count) paket bulundu."
                    } else { output = response.isEmpty ? "Komut gönderildi." : response }
                    busy = false
                }
            } catch {
                DispatchQueue.main.async {
                    output = "Hata: \(error.localizedDescription)"
                    busy = false
                }
            }
        }
    }
}
