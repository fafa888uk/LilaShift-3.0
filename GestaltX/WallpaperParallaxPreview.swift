// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import UIKit

struct WallpaperParallaxPreview: View {
    let image: UIImage
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var drag = CGSize.zero

    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                let offset = reduceMotion ? .zero : CGSize(
                    width: limit(drag.width / 5), height: limit(drag.height / 5)
                )
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .scaleEffect(1.16)
                    .offset(x: -offset.width, y: -offset.height)
                    .overlay(alignment: .top) {
                        TimelineView(.everyMinute) { time in
                            Text(time.date, format: .dateTime.hour().minute())
                                .font(.system(size: 52, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .shadow(radius: 6)
                                .offset(x: offset.width / 2, y: offset.height / 2)
                                .padding(.top, 35)
                        }
                    }
                    .clipped()
                    .clipShape(.rect(cornerRadius: 30))
                    .gesture(DragGesture().updating($drag) { value, state, _ in
                        state = value.translation
                    })
            }
            .frame(height: 360)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L("Wallpaper Parallax Preview"))
            Text(L("Drag the image to preview the layered motion inside LilaShift."))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .navigationTitle(L("Wallpaper Parallax Preview"))
    }

    private func limit(_ value: CGFloat) -> CGFloat {
        min(max(value, -12), 12)
    }
}
