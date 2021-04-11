//
//  ContentView.swift
//  CocoaOrNotCocoa
//

//  Created by Jonathan Wight on 2/3/21.
//

import SwiftUI
import Photos
import CoreML
import Vision

struct OldContentView: View {

    @StateObject
    var model = Model()

    @State
    var width: CGFloat = 64

    let formatter: NumberFormatter = { let f = NumberFormatter()
        f.maximumFractionDigits = 2
        return f
    }()

    @State
    var selection: Model.Record?

    var body: some View {
        HSplitView {
            VStack() {
                browser
                options
            }
            detail(for: selection)
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    var browser: some View {
        GeometryReader { proxy in
            ScrollView(.vertical) {
                LazyVGrid(columns: Array(repeating: .init(.fixed(width)), count: Int(floor(proxy.size.width / (width + 8)))), spacing: 8) {
                    ForEach(model.records) { record in
                        cell(for: record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    func cell(for record: Model.Record) -> some View {
        VStack {
            PhotoAssetView(asset: record.asset, requestSize: CGSize(width: width, height: width))
                .frame(width: width, height: width)
            Text("\(record.prediction.map({ formatter.string(for: $0 * 100)! }) ?? "?")")
                .foregroundColor(record.prediction.map { $0 > 0.5 ? .green : .gray })
        }
        .padding(4)
        .background(selection?.id == record.id ? Color.green : Color.clear)
        .overlay(badge(for: record), alignment: .topTrailing)
        .onTapGesture {
            selection = record
        }
    }

    @ViewBuilder
    func detail(for record: Model.Record?) -> some View {
        if let record = record {
            ZStack {
                Color.white
                PhotoAssetView(asset: record.asset)
            }
        }
    }

    @ViewBuilder
    func badge(for record: Model.Record) -> some View {
        if model.recordIsCocoa(record) {
            Text("C").padding(4).background(Circle().fill(Color.yellow))
        }
    }

    @ViewBuilder
    var options: some View {
        VStack {
            Text("\(model.records.filter({$0.prediction != nil}).count) / \(model.records.count)")
            HStack() {
                Button("Load") {
                    model.load()
                }
                Button("Start") {
                    model.start()
                }
                Button("Stop") {
                    model.stop()
                }
                Button("Export") {

                    let data = try! JSONEncoder().encode(model.records.filter() { $0.prediction != nil })
                    try! data.write(to: URL(fileURLWithPath: "/Users/schwa/Downloads/test.json"))

                }
            }
            Slider(value: $width, in: 16...512)
        }
        .padding()
        .background(Color.white)
        .padding()
        .frame(width: 240)
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

extension NSImage {
    var cgImage: CGImage {
        return cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
}

struct PhotoAssetView: View {
    let asset: PHAsset

    @State
    var image: NSImage?

    var requestSize: CGSize

    init(asset: PHAsset, requestSize: CGSize? = nil) {
        self.asset = asset
        self.requestSize = requestSize ?? CGSize(width: asset.pixelWidth, height: asset.pixelWidth)
    }

    var body: some View {
        if let image = image {
            Image(nsImage: image).resizable().scaledToFit()
        }
        else {
            Color.white.onAppear() {
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = false
                PHImageManager.default().requestImage(for: asset, targetSize: requestSize/*CGSize(width: asset.pixelWidth, height: asset.pixelHeight)*/, contentMode: .aspectFit, options: options) { image, info in
                    self.image = image
                }
            }
        }
    }
}

extension Model {
    func recordIsCocoa(_ record: Record) -> Bool {
        collectionsForID[record.asset.localIdentifier] != nil
    }
}
