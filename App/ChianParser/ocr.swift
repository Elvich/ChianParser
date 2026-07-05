import Cocoa
import Vision

let args = CommandLine.arguments
guard args.count > 1 else {
    print("Usage: swift ocr.swift <path>")
    exit(1)
}

let path = args[1]
guard let image = NSImage(contentsOfFile: path),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Failed to load image")
    exit(1)
}

let request = VNRecognizeTextRequest { request, error in
    guard let observations = request.results as? [VNRecognizedTextObservation], error == nil else { return }
    let text = observations.compactMap({ $0.topCandidates(1).first?.string }).joined(separator: "\n")
    print(text)
}
request.recognitionLanguages = ["ru-RU", "en-US"]

let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
try? handler.perform([request])
