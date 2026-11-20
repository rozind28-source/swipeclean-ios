import SwiftUI

struct SessionCompleteView: View {
    let deletedCount: Int
    let freedBytes: Int64
    let onFinish: () -> Void

    @State private var bounceAnimation: Bool = false

    var body: some View {
        ZStack {
            Color(red: 11/255, green: 12/255, blue: 16/255)
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                // Иконка завершения с пружинящим эффектом .symbolEffect(.bounce)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80))
                    .foregroundColor(Color(red: 34/255, green: 197/255, blue: 94/255))
                    .symbolEffect(.bounce, value: bounceAnimation)
                    .onAppear {
                        bounceAnimation.toggle()
                    }

                VStack(spacing: 8) {
                    Text("Медиатека очищена!")
                        .font(.title.weight(.bold))
                        .foregroundColor(.white)

                    Text("Вы успешно освободили память устройства")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                // Карточка статистики сессии
                HStack(spacing: 20) {
                    VStack(spacing: 6) {
                        Text("\(deletedCount)")
                            .font(.title.weight(.bold))
                            .foregroundColor(.white)
                        Text("Удалено файлов")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)

                    Divider()
                        .frame(height: 40)
                        .background(Color.white.opacity(0.1))

                    VStack(spacing: 6) {
                        Text(ByteFormatter.format(freedBytes))
                            .font(.title.weight(.bold))
                            .foregroundColor(Color(red: 99/255, green: 102/255, blue: 241/255))
                        Text("Освобождено места")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 20)
                .padding(.horizontal, 16)
                .background(Color(red: 22/255, green: 24/255, blue: 31/255))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 1)
                )
                .padding(.horizontal, 24)

                // Памятка про 30 дней и синхронное удаление из iCloud
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundColor(Color(red: 245/255, green: 158/255, blue: 11/255))
                        Text("Где сейчас эти файлы?")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                    }

                    Text("Удалённые фото и видео перемещены в системный альбом «Недавно удалённые». Они будут окончательно стёрты через 30 дней, либо вы можете очистить альбом вручную в приложении «Фото».\n\nФайлы также синхронно удалены из вашего хранилища iCloud.")
                        .font(.caption)
                        .foregroundColor(.gray.opacity(0.9))
                        .lineSpacing(3)
                }
                .padding(16)
                .background(Color(red: 22/255, green: 24/255, blue: 31/255).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 24)

                Spacer()

                // Кнопка возврата «На главную»
                Button {
                    onFinish()
                } label: {
                    Text("На главную")
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(red: 99/255, green: 102/255, blue: 241/255))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
    }
}
