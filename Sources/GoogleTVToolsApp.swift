import SwiftUI

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

    private var visiblePackages: [String] {
        packages.filter {
            (showSystem || !$0.hasPrefix("com.android.")) &&
            (query.isEmpty || $0.localizedCaseInsensitiveContains(query))
        }
    }
    var body: some View {
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
                    Section("Kumanda") {
                        HStack { Spacer(); key("↑", 19); Spacer() }
                        HStack { Spacer(); key("←", 21); key("OK", 23); key("→", 22); Spacer() }
                        HStack { Spacer(); key("↓", 20); Spacer() }
                        HStack { key("Geri", 4); key("Ana ekran", 3); key("Menü", 82) }
                        HStack { key("Ses −", 25); key("Sessiz", 164); key("Ses +", 24) }
                    }
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
                            }
                        }
                    }
                    Section("Cihaz bilgileri") {
                        Button("Depolama") { run("df -h /data") }
                        Button("Android sürümü") { run("getprop ro.build.version.release") }
                        Button("TV'yi yeniden başlat") { run("reboot") }
                    }
                }
                if !output.isEmpty {
                    Section("Komut çıktısı") {
                        Text(output).font(.caption.monospaced()).textSelection(.enabled)
                    }
                }
                Section("Önemli") {
                    Text("Bu sürüm yalnızca klasik ADB TCP (genellikle 5555 portu) ile çalışır. Google TV'nin 6 haneli Kablosuz Hata Ayıklama eşleştirmesi henüz desteklenmez.")
                    Text("Sistem uygulamalarını devre dışı bırakmak televizyonun çalışmasını bozabilir.")
                }.font(.footnote)
            }
            .navigationTitle("Google TV Tools")
            .overlay {
                if busy {
                    ProgressView("İşleniyor…")
                        .padding(24).background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
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
