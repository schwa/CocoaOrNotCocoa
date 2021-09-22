//
//  TrainingModel.swift
//  CocoaOrNotCocoa
//
//  Created by Jonathan Wight on 2/12/21.
//

import Combine
import CreateML
import Foundation
import Photos
import UniformTypeIdentifiers

class TrainingModel: ObservableObject {

    var cancellables: Set <AnyCancellable> = []

    func training(url: URL) throws {
        let labels = try FileManager().contentsOfDirectory(atPath: url.path).filter({ $0.first != "." })
        let urls = labels.map { label -> (String, [URL]) in
            let url = url.appendingPathComponent(label)
            let fileManager = FileManager()
            let urls = fileManager.enumerator(at: url, includingPropertiesForKeys: [.typeIdentifierKey], options: .skipsSubdirectoryDescendants, errorHandler: nil)!
            .map {
                $0 as! URL
            }
            .filter { url in
                guard let contentType = try! url.resourceValues(forKeys: [.contentTypeKey]).contentType else {
                    print(url)
                    return false
                }
                return contentType.conforms(to: UTType.image)
            }
            return (label, urls.shuffled())
        }
        .map { label, urls -> (String, [URL], [URL]) in
            print(urls.count)
            let trainingURLs = Array(urls[..<1000])
            let evaluationURLs = Array(urls[1000..<1200])
            return (label, trainingURLs, evaluationURLs)
        }

// print(urls)

        let trainingData = MLImageClassifier.DataSource.filesByLabel(Dictionary(uniqueKeysWithValues: urls.map { label, trainingURLs, _ in
            return (label, trainingURLs)
        }))
        let evaluationData = MLImageClassifier.DataSource.filesByLabel(Dictionary(uniqueKeysWithValues: urls.map { label, _, evaluationURLs in
            return (label, evaluationURLs)
        }))

        let v = MLImageClassifier.ModelParameters.ValidationData.dataSource(evaluationData)

        let parameters = MLImageClassifier.ModelParameters(validation: v, maxIterations: 25, augmentation: MLImageClassifier.ImageAugmentationOptions())

        let sessionParameters = MLTrainingSessionParameters(
            sessionDirectory: nil, // URL(fileURLWithPath: "/Volumes/ramdisk/Checkpoints"),
            reportInterval: 5,
            checkpointInterval: 10,
            iterations: 1000
        )

        let job = try MLImageClassifier.train(trainingData: trainingData, parameters: parameters, sessionParameters: sessionParameters)

        job.progress.publisher(for: \.fractionCompleted)
        .sink { fractionCompleted in
            print("Progress: \(fractionCompleted)")
        }
        .store(in: &cancellables)

        job.checkpoints
        .assertNoFailure()
        .sink { result in
            print("1", result)
        }
        receiveValue: { model in
            print("2", model)
        }
        .store(in: &cancellables)

        job.result
        .sink { result in
            print("3", result)
        }
        receiveValue: { model in
            print("4", model)
        }
        .store(in: &cancellables)

//        let classifier = try MLImageClassifier(trainingData: .filesByLabel(trainingData))
//        let metrics = classifier.evaluation(on: .filesByLabel(evaluationData))
//        print(metrics)

// MLImageClassifier.train(trainingData: (<#T##[String : [URL]]#>))

    }

}
