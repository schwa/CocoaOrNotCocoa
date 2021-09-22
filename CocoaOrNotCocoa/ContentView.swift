//
//  ContentView.swift
//  CocoaOrNotCocoa
//
//  Created by Jonathan Wight on 2/12/21.
//

import SwiftUI
import Photos
import Combine
import UniformTypeIdentifiers
// import Everything

struct ContentView: View {

    @StateObject
    var library = PhotoLibrary()

    @StateObject
    var trainingModel = TrainingModel()

    var body: some View {
        List {
            ForEach(library.albums) { album in
                Text("\(album.title) \(album.assets.count)")
            }
        }
        Button("Export") {

            if !FileManager().fileExists(atPath: "/tmp/TrainingData") {
                try! FileManager().createDirectory(atPath: "/tmp/TrainingData", withIntermediateDirectories: true, attributes: nil)
            }

            let parentProgress = Progress(totalUnitCount: 2)

            parentProgress.publisher(for: \.fractionCompleted)
            .sink { _ in
            }
            .store(in: &cancellables)

            let exporters = ["Cocoa"/*, "Not Cocoa"*/].map { title -> AnyPublisher<(PhotoLibrary.Asset, Result<URL, Error>), Error> in
                let album = library.albums.first(where: { $0.title == title })
                let url = URL(fileURLWithPath: "/tmp/TrainingData/\(title)")
                try? FileManager().createDirectory(at: url, withIntermediateDirectories: true, attributes: nil)
                let progress = Progress(totalUnitCount: Int64(album!.assets.count), parent: parentProgress, pendingUnitCount: 1)
                return album!.export(url: url).handleEvents(receiveRequest: { _ in
                    print("TICK")
                    progress.completedUnitCount += 1
                })
                .eraseToAnyPublisher()
            }
            Publishers.MergeMany(exporters)
//            .debounce(for: 0.1, scheduler: DispatchQueue.main)
//            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .assertNoFailure()
            .sink { _ in
                print("Complete")
//                print("Requested: \(PhotoLibrary.Asset.requested.count)")
//                print("Received: \(PhotoLibrary.Asset.received.count)")
            }
            .store(in: &cancellables)
        }
        Button("Train") {
            let url = URL(fileURLWithPath: "/tmp/TrainingData")
            try! trainingModel.training(url: url)
        }

    }
}

var cancellables: Set <AnyCancellable> = []

class PhotoLibrary: ObservableObject {
    var albums: [Album] = []

    class Album: Identifiable {
        let id = UUID()
        var phCollection: PHAssetCollection
        var assets: [Asset] = []

        init(phCollection: PHAssetCollection) {
            self.phCollection = phCollection
            PHAsset.fetchAssets(in: self.phCollection, options: nil).enumerateObjects { asset, _, _ in
                self.assets.append(Asset(album: self, phAsset: asset))
            }
        }

        var title: String {
            phCollection.localizedTitle!
        }

        var cancellables: Set <AnyCancellable> = []

        func export(url: URL) -> AnyPublisher<(Asset, Result<URL, Error>), Error> {
            print("Assets \(assets.count)")
            return Publishers.Sequence(sequence: assets)
            .flatMap { asset -> AnyPublisher<(Asset, Result<NSImage, Error>), Never> in
                asset.requestImage(size: CGSize(width: 160, height: 160), contentMode: .aspectFit)
                .result()
                .map { (asset, $0) }
                .eraseToAnyPublisher()
            }
            .tryMap { (asset, result) -> (Asset, Result<URL, Error>) in
                switch result {
                case let .success(image):
                    let id = asset.phAsset.localIdentifier.replacingOccurrences(of: "/", with: "_")
                    let url = url.appendingPathComponent("\(id).tiff")
                    try image.tiffRepresentation!.write(to: url)

                    return (asset, Result<URL, Error>.success(url))
                case let .failure(error):
                    return (asset, Result<URL, Error>.failure(error))
                }
            }
            .eraseToAnyPublisher()
        }
    }

    class Asset: Identifiable {
        let id = UUID()
        weak var album: Album!
        let phAsset: PHAsset

        init(album: Album, phAsset: PHAsset) {
            self.album = album
            self.phAsset = phAsset
        }

        static var requested: Set<AnyHashable> = []
        static var received: Set<AnyHashable> = []

        func requestImage(size: CGSize? = nil, contentMode: PHImageContentMode = .default, options: PHImageRequestOptions? = nil) -> AnyPublisher<NSImage, Error> {
            let size = size ?? CGSize(width: phAsset.pixelWidth, height: phAsset.pixelHeight)
            let subject = PassthroughSubject<NSImage, Error>()
            let id = PHImageManager.default().requestImage(for: phAsset, targetSize: size, contentMode: contentMode, options: options) { image, info in
                if let error = info?[PHImageErrorKey] {
                    subject.send(completion: .failure(error as! Error))
                } else if let image = image {
                    subject.send(image)
                    if info?[PHImageResultIsDegradedKey].map({ $0 as! Bool }) == false {
                        subject.send(completion: .finished)
                        let id = info?[PHImageResultRequestIDKey] as! AnyHashable
                        _ = Asset.received.insert(id)
                    }
                }
            }
            _ = Asset.requested.insert(id)

            return subject.eraseToAnyPublisher()
        }
    }

    init() {
        PHCollectionList.fetchTopLevelUserCollections(with: nil).enumerateObjects { collection, _, _ in
            if let collection = collection as? PHAssetCollection {
                self.albums.append(Album(phCollection: collection))
            }
        }
    }
}

extension Publisher {
    func result() -> AnyPublisher<Result<Output, Failure>, Never> {
        map { .success($0) }
        .catch {
            Just(.failure($0))
        }
        .eraseToAnyPublisher()
    }
}
