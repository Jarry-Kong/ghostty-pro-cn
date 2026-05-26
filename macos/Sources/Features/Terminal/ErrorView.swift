import SwiftUI

struct ErrorView: View {
    var body: some View {
        HStack {
            Image("AppIconImage")
                .resizable()
                .scaledToFit()
                .frame(width: 128, height: 128)

            VStack(alignment: .leading) {
                Text("糟糕。😭").font(.title)
                Text("出了点严重问题。\n请查看日志，然后重启 Ghostty。")
            }
        }
        .padding()
    }
}

struct ErrorView_Previews: PreviewProvider {
    static var previews: some View {
        ErrorView()
    }
}
