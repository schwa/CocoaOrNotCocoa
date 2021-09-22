//
//  Model.swift
//  CocoaOrNotCocoa
//
//  Created by Jonathan Wight on 2/3/21.
//

import AppKit
import Photos
import CoreML
import Vision
import Combine
import SwiftUI
import CreateML

func assetPublisher(fetch: PHFetchResult<PHAsset>) -> AnyPublisher <PHAsset, Never> {
    let subject = PassthroughSubject<PHAsset, Never>()
    DispatchQueue.global(qos: .default).async {
        // TODO: what about 0 assets
        fetch.enumerateObjects { (asset, index, _) in
            subject.send(asset)
            if index == fetch.count - 1 {
                subject.send(completion: .finished)
            }
        }
    }
    return subject.eraseToAnyPublisher()
}

class Model: ObservableObject {

    struct Record: Identifiable, Equatable, Encodable {

        enum CodingKeys: CodingKey {
            case assetID
            case prediction
            case collections
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(asset.localIdentifier, forKey: .assetID)
            try container.encode(prediction, forKey: .prediction)
            try container.encode(collections, forKey: .collections)
        }

        let id = UUID()
        var asset: PHAsset
        var prediction: Double?
        var collections: [String] = []
    }

    var recordDict: [String: Record] = [:]

    @Published
    var records: [Record] = []

    @Published
    var started = false

    var backingRecords: [Record] = []
    var cancellables = Set<AnyCancellable>()
    let classifier = try! CocoaOrNotCocoa(contentsOf: Bundle.main.url(forResource: "CocoaOrNotCocoa", withExtension: "mlmodelc")!)
    var updateSubject = PassthroughSubject<[Record], Never>()

    init() {
        updateSubject
            .throttle(for: 0.1, scheduler: DispatchQueue.main, latest: true)
            .sink {
                self.records = $0
            }
            .store(in: &cancellables)
    }

    func load() {
        let fetch = PHAsset.fetchAssets(with: .image, options: nil)
        assetPublisher(fetch: fetch)
            .collect()
            .map {
                $0.sorted { $0.localIdentifier < $1.localIdentifier }
                    .map({ Record(asset: $0) })
            }
            .receive(on: DispatchQueue.main)
            .sink { records in
                self.updateCollectios()
                self.recordDict = Dictionary(uniqueKeysWithValues: records.map({ ($0.asset.localIdentifier, $0) }))
                self.records = records
                self.backingRecords = self.records
            }
            .store(in: &cancellables)
    }

    func updateCollectios() {
        PHCollectionList.fetchTopLevelUserCollections(with: nil).enumerateObjects { collection, _, _ in
            if collection.localizedTitle!.contains("Cocoa") {
                let fetch = PHAsset.fetchAssets(in: collection as! PHAssetCollection, options: nil)
                assetPublisher(fetch: fetch)
                    .collect()
                    .map {
                        $0.map({ $0.localIdentifier })
                    }
                    .receive(on: DispatchQueue.main)
                    .sink { identifiers in
                        for identifier in identifiers {
                            self.recordDict[identifier]!.collections.append(collection.localizedTitle!)
                        }
                    }
                    .store(in: &self.cancellables)
            }
        }
    }

    var collectionsForID: [String: PHAssetCollection] = [:]

    func start() {

        if started {
            return
        }
        started = true

        let jobQueue = DispatchQueue(label: "job", qos: .userInitiated, attributes: .concurrent)
        let workerQueue = DispatchQueue(label: "worker", qos: .userInitiated, attributes: .concurrent)
        let updateQueue = DispatchQueue(label: "update", qos: .default)
        jobQueue.async {
            let options = PHImageRequestOptions()
            options.deliveryMode = .fastFormat
            options.isSynchronous = true

            let group = DispatchGroup()
            let semaphore = DispatchSemaphore(value: ProcessInfo.processInfo.processorCount * 2)

            self.records.enumerated().forEach { index, record in

                if record.prediction != nil {
                    return
                }

                if self.started == false {
                    return
                }

                semaphore.wait()
                workerQueue.async(group: group) {
                    PHImageManager.default().requestImage(for: record.asset, targetSize: CGSize(width: 1080, height: 1080), contentMode: .aspectFill, options: options) { image, _ in
                        let input = try! CocoaOrNotCocoaInput(imageWith: image!.cgImage)
                        let prediction = try! self.classifier.prediction(input: input)
                        var record = record
                        record.prediction = prediction.classLabelProbs["Cocoa"]!
                        updateQueue.async {
                            var backingRecords = self.backingRecords
                            backingRecords[index] = record
                            //                            backingRecords = backingRecords.sorted(by: { $0.prediction ?? 0 > $1.prediction ?? 0 })
                            self.backingRecords = backingRecords
                            self.updateSubject.send(backingRecords)
                        }
                        semaphore.signal()
                    }
                }
            }
            group.wait()
        }
    }

    func stop() {
        self.started = false
    }
}
