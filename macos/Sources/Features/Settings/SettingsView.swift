import SwiftUI

struct SettingsView: View {
    // We need access to our app delegate to know if we're quitting or not.
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text("即将推出。🚧").font(.title)
                Text("图形化设置还在开发中。要修改设置，" +
                     "请编辑 $HOME/.config/ghostty/config 文件，然后重启 Ghostty。")
                .multilineTextAlignment(.leading)
                .lineLimit(nil)
            }
        }
        .padding()
        .frame(minWidth: 500, maxWidth: 500, minHeight: 156, maxHeight: 156)
    }
}

struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}
