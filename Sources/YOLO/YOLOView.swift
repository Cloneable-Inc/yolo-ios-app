//
//  YOLOView.swift
//  Example
//
//  Created by Sample on 2025/03/05.
//

import UIKit
import Vision
import AVFoundation
import Accelerate
import Foundation

// MARK: - トラッカー用クラス

/// バウンディングボックスとクラスラベルを追跡するためのオブジェクト
class TrackedObject {
    var index: Int
    var label: String           // クラスラベル
    var box: CGRect             // 現在のバウンディングボックス
    var score: Float            // 信頼度
    var unDetectedCounter: Int  // 何フレーム未検出が続いたか

    init(index: Int, label: String) {
        self.index = index
        self.label = label
        self.box = .zero
        self.score = 0.0
        self.unDetectedCounter = 0
    }

    /// バウンディングボックスとスコアを更新
    func update(box: CGRect, score: Float) {
        self.box = box
        self.score = score
        self.unDetectedCounter = 0 // 更新されたのでリセット
    }
}

/// バウンディングボックス＆クラスラベルのシンプルトラッカー
class BoxClassTracker {
    /// 現在追跡中のオブジェクト一覧
    var trackedObjects = [TrackedObject]()
    /// 次に割り当てる固有 ID
    var objectIndex: Int = 0

    /// 毎フレーム呼び出して追跡を更新する関数
    ///
    /// - Parameter boxesScoresLabels: (CGRect, Float, String) = (バウンディングボックス, スコア, クラスラベル)
    /// - Returns: 今フレームで表示するべき追跡中オブジェクト
    func track(boxesScoresLabels: [(CGRect, Float, String)]) -> [TrackedObject] {

        // 1) まだ追跡対象がなければ全部追加
        if trackedObjects.isEmpty {
            for detected in boxesScoresLabels {
                let newObj = TrackedObject(index: objectIndex, label: detected.2)
                newObj.update(box: detected.0, score: detected.1)
                objectIndex += 1
                trackedObjects.append(newObj)
            }
            return trackedObjects
        }

        var usedDetectedIndex: Set<Int> = []
        var unDetectedObjectIndexes: [Int] = []

        // 2) 既存のトラックに対して、同じクラスラベル & IoU が最大となる検出を探して更新
        for (ti, trackedObj) in trackedObjects.enumerated() {
            var bestIOU: CGFloat = 0
            var bestIndex: Int? = nil

            for (di, detected) in boxesScoresLabels.enumerated() {
                // クラスラベルが異なる場合は無視
                if trackedObj.label != detected.2 {
                    continue
                }
                let iou = overlapPercentage(rect1: trackedObj.box, rect2: detected.0)
                if iou > bestIOU {
                    bestIOU = iou
                    bestIndex = di
                }
            }

            // IoU >= 50% なら同一オブジェクトとみなして更新
            if let bestIndex = bestIndex, bestIOU >= 50 {
                let det = boxesScoresLabels[bestIndex]
                trackedObjects[ti].update(box: det.0, score: det.1)
                usedDetectedIndex.insert(bestIndex)
            } else {
                // 更新できなかったら未検出
                unDetectedObjectIndexes.append(ti)
            }
        }

        // 3) 更新できなかったトラックは未検出カウンタを増やす
        for idx in unDetectedObjectIndexes {
            trackedObjects[idx].unDetectedCounter += 1
        }

        // 4) 割り当てられなかった(新規)検出を追加
        for (di, det) in boxesScoresLabels.enumerated() {
            if !usedDetectedIndex.contains(di) {
                let newObj = TrackedObject(index: objectIndex, label: det.2)
                newObj.update(box: det.0, score: det.1)
                objectIndex += 1
                trackedObjects.append(newObj)
            }
        }

        // 同じクラスラベル同士で過度に重なるトラックを削除(90%以上重複したら先のほうを削除)
        trackedObjects = removeOverlappingRects(trackedObjects: trackedObjects, threshold: 90.0)

        // 5) フレーム内で未検出が一定回数(15回等)を越えたらリストから削除
        var objectsToShow: [TrackedObject] = []
        var removeIndexes: [Int] = []
        for (i, obj) in trackedObjects.enumerated() {
            if obj.unDetectedCounter == 0 {
                objectsToShow.append(obj)
            } else if obj.unDetectedCounter >= 15 {
                removeIndexes.append(i)
            }
        }
        for idx in removeIndexes.sorted(by: >) {
            trackedObjects.remove(at: idx)
        }

        return objectsToShow
    }
}

/// 2つの矩形の重なり度合いを rect1 の面積に対するパーセンテージで返す
func overlapPercentage(rect1: CGRect, rect2: CGRect) -> CGFloat {
    let intersection = rect1.intersection(rect2)
    if intersection.isNull {
        return 0.0
    }
    let intersectionArea = intersection.width * intersection.height
    let rect1Area = rect1.width * rect1.height
    let overlapPercentage = (intersectionArea / rect1Area) * 100
    return overlapPercentage
}

/// 同じクラスラベル同士で過度に重なる(例: 90%以上)矩形があった場合に先の要素を削除する
func removeOverlappingRects(
    trackedObjects: [TrackedObject],
    threshold: CGFloat = 90.0
) -> [TrackedObject] {
    var filtered = trackedObjects
    var i = 0
    while i < filtered.count {
        var shouldRemove = false
        let currentObj = filtered[i]
        // 同じラベルのオブジェクト同士のみ判定
        for j in (i + 1)..<filtered.count {
            let nextObj = filtered[j]
            if currentObj.label == nextObj.label {
                let percentage = overlapPercentage(rect1: currentObj.box, rect2: nextObj.box)
                if percentage >= threshold {
                    shouldRemove = true
                    break
                }
            }
        }
        if shouldRemove {
            filtered.remove(at: i)
        } else {
            i += 1
        }
    }
    return filtered
}

// MARK: - YOLOView

@MainActor
public class YOLOView: UIView, VideoCaptureDelegate {
    private var classColors: [String: UIColor] = [:]
    
    /// クラスに応じたランダムカラーを返す。初回のみ生成し、以後は同じクラスに同じ色を返す
    private func colorForClass(_ className: String) -> UIColor {
        if let existing = classColors[className] {
            return existing
        } else {
            let newColor = UIColor(
                hue: CGFloat.random(in: 0...1),
                saturation: CGFloat.random(in: 0.6...1),
                brightness: CGFloat.random(in: 0.6...1),
                alpha: 1.0
            )
            classColors[className] = newColor
            return newColor
        }
    }

    // トラッキングのオンオフ
    private var trackingSwitch = UISwitch()
    private var labelTrackingSwitch = UILabel()
    var isTrackingOn = false
    
    // BoxClassTrackerをインスタンス化
    private var boxClassTracker = BoxClassTracker()
    
    func onInferenceTime(speed: Double, fps: Double) {
        DispatchQueue.main.async {
            self.labelFPS.text = String(format: "%.1f FPS - %.1f ms", fps, speed)
        }
    }
    
    func onPredict(result: YOLOResult) {
        
        DispatchQueue.main.async {
            // detect/segment/pose は共通で result.boxes を持つ
            if self.task == .detect || self.task == .segment || self.task == .pose {
                if self.isTrackingOn {
                    // トラッキングあり
                    let detections: [(CGRect, Float, String)] = result.boxes.map { box in
                        // xywhnをそのままトラッカーに渡す(ラベルは box.cls)
                        return (box.xywhn, box.conf, box.cls)
                    }
                    let trackedObjs = self.boxClassTracker.track(boxesScoresLabels: detections)
                    // トラッキング後の表示
                    self.showBoxesFromTracker(trackedObjs: trackedObjs, predictions: result)
                } else {
                    // 通常表示
                    self.showBoxes(predictions: result)
                }
            }
            else if self.task == .classify {
                self.overlayYOLOClassificationsCALayer(on: self, result: result)
            }
            else if self.task == .obb {
                guard let obbLayer = self.obbLayer else { return }
                let obbDetections = result.obb
                self.obbRenderer.drawObbDetectionsWithReuse(
                    obbDetections: obbDetections,
                    on: obbLayer,
                    imageViewSize: self.overlayLayer.frame.size,
                    originalImageSize: result.orig_shape,
                    lineWidth: 3
                )
            }
            
            // セグメンテーションマスクの描画
            if self.task == .segment {
                if let maskImage = result.masks?.combinedMask {
                    guard let maskLayer = self.maskLayer else { return }
                    maskLayer.isHidden = false
                    maskLayer.frame = self.overlayLayer.bounds
                    maskLayer.contents = maskImage
                    self.videoCapture.predictor.isUpdating = false
                } else {
                    self.videoCapture.predictor.isUpdating = false
                }
            }
            
            // ポーズ推定での keypoints の描画 (boxes もあれば合わせて利用可能)
            if self.task == .pose {
                self.removeAllSubLayers(parentLayer: self.poseLayer)
                var keypointList = [[(x:Float, y:Float)]]()
                var confsList = [[Float]]()
                
                for keypoint in result.keypointsList {
                    keypointList.append(keypoint.xyn)
                    confsList.append(keypoint.conf)
                }
                guard let poseLayer = self.poseLayer else { return }
                drawKeypoints(keypointsList: keypointList,
                                   confsList: confsList,
                                   boundingBoxes: result.boxes,
                                   on: poseLayer,
                                   imageViewSize: self.overlayLayer.frame.size,
                                   originalImageSize: result.orig_shape)
            }
        }
    }
    
    // トラッキングありの場合の描画
    // クラスごとに同じ色を使い、ラベルには "#ID" をつける
    func showBoxesFromTracker(trackedObjs: [TrackedObject], predictions: YOLOResult) {
        
        let width = self.bounds.width
        let height = self.bounds.height
        let resultCount = trackedObjs.count
        
        if UIDevice.current.orientation == .portrait {
            var ratio: CGFloat = 1.0
            if videoCapture.captureSession.sessionPreset == .photo {
                ratio = (height / width) / (4.0 / 3.0)
            } else {
                ratio = (height / width) / (16.0 / 9.0)
            }
            
            self.labelSliderNumItems.text = "\(resultCount) items (max \(Int(sliderNumItems.value)))"
            
            for i in 0..<boundingBoxViews.count {
                if i < resultCount && i < 50 {
                    let obj = trackedObjs[i]
                    
                    // 座標は xywhn 想定 -> y反転して使う
                    var rect = CGRect(
                        x: obj.box.minX,
                        y: 1 - obj.box.maxY,
                        width: obj.box.width,
                        height: obj.box.height
                    )
                    
                    // クラス名
                    let bestClass = obj.label
                    let confidence = CGFloat(obj.score)
                    
                    // クラスごとに色を決める: result.names から index を探す
                    var colorIndex = 0
                    if let cIndex = predictions.names.firstIndex(of: bestClass) {
                        colorIndex = cIndex % ultralyticsColors.count
                    }
                    let boxColor = colorForClassID(obj.index)

                    
                    // ラベルに ID を併記 (例: "person #2 85.0")
                    let label = String(format: "%@ id:%d %.1f", bestClass, obj.index, confidence * 100)
                    
                    // 不透明度
                    let alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
                    
                    // 端末の回転対応
                    var displayRect = rect
                    switch UIDevice.current.orientation {
                    case .portraitUpsideDown:
                        displayRect = CGRect(
                            x: 1.0 - rect.origin.x - rect.width,
                            y: 1.0 - rect.origin.y - rect.height,
                            width: rect.width,
                            height: rect.height
                        )
                    default: break
                    }
                    
                    // アスペクト比の補正
                    if ratio >= 1 {
                        let offset = (1 - ratio) * (0.5 - displayRect.minX)
                        let transform = CGAffineTransform(scaleX: 1, y: -1)
                            .translatedBy(x: offset, y: -1)
                        displayRect = displayRect.applying(transform)
                        displayRect.size.width *= ratio
                    } else {
                        let offset = (ratio - 1) * (0.5 - displayRect.maxY)
                        let transform = CGAffineTransform(scaleX: 1, y: -1)
                            .translatedBy(x: 0, y: offset - 1)
                        displayRect = displayRect.applying(transform)
                        displayRect.size.width *= ratio
                    }
                    
                    displayRect = VNImageRectForNormalizedRect(displayRect, Int(width), Int(height))
                    
                    boundingBoxViews[i].show(
                        frame: displayRect,
                        label: label,
                        color: boxColor,
                        alpha: alpha
                    )
                    
                } else {
                    boundingBoxViews[i].hide()
                }
            }
        }
        else {
            // 横向きレイアウト
            let frameAspectRatio = videoCapture.longSide / videoCapture.shortSide
            let viewAspectRatio = width / height
            var scaleX: CGFloat = 1.0
            var scaleY: CGFloat = 1.0
            var offsetX: CGFloat = 0.0
            var offsetY: CGFloat = 0.0
            
            if frameAspectRatio > viewAspectRatio {
                scaleY = height / videoCapture.shortSide
                scaleX = scaleY
                offsetX = (videoCapture.longSide * scaleX - width) / 2
            } else {
                scaleX = width / videoCapture.longSide
                scaleY = scaleX
                offsetY = (videoCapture.shortSide * scaleY - height) / 2
            }
            
            for i in 0..<boundingBoxViews.count {
                if i < resultCount && i < 50 {
                    let obj = trackedObjs[i]
                    
                    var rect = CGRect(
                        x: obj.box.minX,
                        y: 1 - obj.box.maxY,
                        width: obj.box.width,
                        height: obj.box.height
                    )
                    
                    let bestClass = obj.label
                    let confidence = CGFloat(obj.score)
                    
                    var colorIndex = 0
                    if let cIndex = predictions.names.firstIndex(of: bestClass) {
                        colorIndex = cIndex % ultralyticsColors.count
                    }
                    let boxColor = colorForClassID(obj.index)
                    
                    let label = String(format: "%@ #%d %.1f", bestClass, obj.index, confidence * 100)
                    let alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
                    
                    rect.origin.x = rect.origin.x * videoCapture.longSide * scaleX - offsetX
                    rect.origin.y = height - (rect.origin.y * videoCapture.shortSide * scaleY
                                              - offsetY
                                              + rect.size.height * videoCapture.shortSide * scaleY)
                    rect.size.width *= videoCapture.longSide * scaleX
                    rect.size.height *= videoCapture.shortSide * scaleY
                    
                    boundingBoxViews[i].show(
                        frame: rect,
                        label: label,
                        color: boxColor,
                        alpha: alpha
                    )
                } else {
                    boundingBoxViews[i].hide()
                }
            }
        }
    }
    
    // 以下、通常の showBoxes() や UI 設定など既存の処理 -----------------------------
    
    var onDetection: ((YOLOResult) -> Void)?
    private var videoCapture: VideoCapture
    private var busy = false
    private var currentBuffer: CVPixelBuffer?
    var framesDone = 0
    var t0 = 0.0
    var t1 = 0.0
    var t2 = 0.0
    var t3 = CACurrentMediaTime()
    var t4 = 0.0
    var task = YOLOTask.detect
    var colors: [String: UIColor] = [:]
    var modelName: String = ""
    var classes: [String] = []
    let maxBoundingBoxViews = 100
    var boundingBoxViews = [BoundingBoxView]()
    public var sliderNumItems = UISlider()
    public var labelSliderNumItems = UILabel()
    public var sliderConf = UISlider()
    public var labelSliderConf = UILabel()
    public var sliderIoU = UISlider()
    public var labelSliderIoU = UILabel()
    public var labelName = UILabel()
    public var labelFPS = UILabel()
    public var labelZoom = UILabel()
    public var activityIndicator = UIActivityIndicatorView()
    public var playButton = UIButton()
    public var pauseButton = UIButton()
    public var switchCameraButton = UIButton()
    public var toolbar = UIView()
    let selection = UISelectionFeedbackGenerator()
    private var overlayLayer = CALayer()
    private var maskLayer: CALayer?
    private var poseLayer: CALayer?
    private var obbLayer: CALayer?
    
    let obbRenderer = OBBRenderer()
    
    private let minimumZoom: CGFloat = 1.0
    private let maximumZoom: CGFloat = 10.0
    private var lastZoomFactor: CGFloat = 1.0
    
    public var capturedImage: UIImage?
    private var photoCaptureCompletion: ((UIImage?) -> Void)?
    
    public init(
        frame: CGRect,
        modelPathOrName: String,
        task: YOLOTask) {
            self.videoCapture = VideoCapture()
            super.init(frame: frame)
            setModel(modelPathOrName: modelPathOrName, task: task)
            setUpOrientationChangeNotification()
            self.setUpBoundingBoxViews()
            self.setupUI()
            self.videoCapture.delegate = self
            start(position: .back)
            setupOverlayLayer()
        }
    
    required init?(coder: NSCoder) {
        self.videoCapture = VideoCapture()
        super.init(coder: coder)
    }
    
    public override func awakeFromNib() {
        super.awakeFromNib()
        Task { @MainActor in
            setUpOrientationChangeNotification()
            setUpBoundingBoxViews()
            setupUI()
            videoCapture.delegate = self
            start(position: .back)
            setupOverlayLayer()
        }
    }
    
    public func setModel(
        modelPathOrName: String,
        task: YOLOTask,
        completion: ((Result<Void, Error>) -> Void)? = nil
    ) {
        activityIndicator.startAnimating()
        boundingBoxViews.forEach { box in
            box.hide()
        }
        removeClassificationLayers()
        
        self.task = task
        setupSublayers()
        
        var modelURL: URL?
        let lowercasedPath = modelPathOrName.lowercased()
        let fileManager = FileManager.default
        
        // Determine model URL
        if lowercasedPath.hasSuffix(".mlmodel")
            || lowercasedPath.hasSuffix(".mlpackage")
            || lowercasedPath.hasSuffix(".mlmodelc") {
            let possibleURL = URL(fileURLWithPath: modelPathOrName)
            if fileManager.fileExists(atPath: possibleURL.path) {
                modelURL = possibleURL
            }
        } else {
            if let compiledURL = Bundle.main.url(forResource: modelPathOrName, withExtension: "mlmodelc") {
                modelURL = compiledURL
            } else if let packageURL = Bundle.main.url(forResource: modelPathOrName, withExtension: "mlpackage") {
                modelURL = packageURL
            }
        }
        
        guard let unwrappedModelURL = modelURL else {
            let error = PredictorError.modelFileNotFound
            fatalError(error.localizedDescription)
        }
        
        modelName = unwrappedModelURL.deletingPathExtension().lastPathComponent
        
        // Common success handling
        func handleSuccess(predictor: Predictor) {
            self.videoCapture.predictor = predictor
            self.activityIndicator.stopAnimating()
            self.labelName.text = modelName
            completion?(.success(()))
        }
        
        // Common failure handling
        func handleFailure(_ error: Error) {
            print("Failed to load model with error: \(error)")
            self.activityIndicator.stopAnimating()
            completion?(.failure(error))
        }
        
        switch task {
        case .classify:
            Classifier.create(unwrappedModelURL: unwrappedModelURL,isRealTime: true) { [weak self] result in
                switch result {
                case .success(let predictor):
                    handleSuccess(predictor: predictor)
                case .failure(let error):
                    handleFailure(error)
                }
            }
        case .segment:
            Segmenter.create(unwrappedModelURL: unwrappedModelURL,isRealTime: true) { [weak self] result in
                switch result {
                case .success(let predictor):
                    handleSuccess(predictor: predictor)
                case .failure(let error):
                    handleFailure(error)
                }
            }
        case .pose:
            PoseEstimater.create(unwrappedModelURL: unwrappedModelURL,isRealTime: true) { [weak self] result in
                switch result {
                case .success(let predictor):
                    handleSuccess(predictor: predictor)
                case .failure(let error):
                    handleFailure(error)
                }
            }
        case .obb:
            ObbDetector.create(unwrappedModelURL: unwrappedModelURL,isRealTime: true) { [weak self] result in
                switch result {
                case .success(let predictor):
                    self?.obbLayer?.isHidden = false
                    handleSuccess(predictor: predictor)
                case .failure(let error):
                    handleFailure(error)
                }
            }
        default:
            ObjectDetector.create(unwrappedModelURL: unwrappedModelURL,isRealTime: true) { [weak self] result in
                switch result {
                case .success(let predictor):
                    handleSuccess(predictor: predictor)
                case .failure(let error):
                    handleFailure(error)
                }
            }
        }
    }
    
    private func start(position: AVCaptureDevice.Position){
        if !busy {
            busy = true
            videoCapture.setUp(sessionPreset: .photo, position: position) { success in
                if success {
                    if let previewLayer = self.videoCapture.previewLayer {
                        self.layer.insertSublayer(previewLayer, at: 0)
                        self.videoCapture.previewLayer?.frame = self.bounds
                        for box in self.boundingBoxViews {
                            box.addToLayer(previewLayer)
                        }
                    }
                    self.videoCapture.previewLayer?.addSublayer(self.overlayLayer)
                    self.videoCapture.start()
                    self.busy = false
                }
            }
        }
    }
    
    public func stop(){
        videoCapture.stop()
    }
    
    public func resume(){
        videoCapture.start()
    }
    
    func setUpBoundingBoxViews() {
        while boundingBoxViews.count < maxBoundingBoxViews {
            boundingBoxViews.append(BoundingBoxView())
        }
    }
    
    func setupOverlayLayer() {
        let width = self.bounds.width
        let height = self.bounds.height
        
        var ratio: CGFloat = 1.0
        if videoCapture.captureSession.sessionPreset == .photo {
            ratio = (4.0 / 3.0)
        } else {
            ratio = (16.0 / 9.0)
        }
        var offSet = CGFloat.zero
        var margin = CGFloat.zero
        if self.bounds.width < self.bounds.height {
            offSet = height / ratio
            margin = (offSet - self.bounds.width) / 2
            self.overlayLayer.frame = CGRect(
                x: -margin, y: 0, width: offSet, height: self.bounds.height)
        } else {
            offSet = width / ratio
            margin = (offSet - self.bounds.height) / 2
            self.overlayLayer.frame = CGRect(
                x: 0, y: -margin, width: self.bounds.width, height: offSet)
        }
    }
    
    func setupMaskLayerIfNeeded() {
        if maskLayer == nil {
            let layer = CALayer()
            layer.frame = self.overlayLayer.bounds
            layer.opacity = 0.5
            layer.name = "maskLayer"
            self.overlayLayer.addSublayer(layer)
            self.maskLayer = layer
        }
    }
    
    func setupPoseLayerIfNeeded() {
        if poseLayer == nil {
            let layer = CALayer()
            layer.frame = self.overlayLayer.bounds
            layer.opacity = 0.5
            self.overlayLayer.addSublayer(layer)
            self.poseLayer = layer
        }
    }
    
    func setupObbLayerIfNeeded() {
        if obbLayer == nil {
            let layer = CALayer()
            layer.frame = self.overlayLayer.bounds
            layer.opacity = 0.5
            self.overlayLayer.addSublayer(layer)
            self.obbLayer = layer
        }
    }
    
    public func resetLayers() {
        removeAllSubLayers(parentLayer: maskLayer)
        removeAllSubLayers(parentLayer: poseLayer)
        removeAllSubLayers(parentLayer: overlayLayer)
        
        maskLayer = nil
        poseLayer = nil
        obbLayer?.isHidden = true
    }
    
    func setupSublayers() {
        resetLayers()
        
        switch task {
        case .segment:
            setupMaskLayerIfNeeded()
        case .pose:
            setupPoseLayerIfNeeded()
        case .obb:
            setupObbLayerIfNeeded()
            overlayLayer.addSublayer(obbLayer!)
            obbLayer?.isHidden = false
        default:break
        }
    }
    
    func removeAllSubLayers(parentLayer:CALayer?) {
        guard let parentLayer = parentLayer else { return }
        parentLayer.sublayers?.forEach { layer in
            layer.removeFromSuperlayer()
        }
        parentLayer.sublayers = nil
        parentLayer.contents = nil
    }
    
    func addMaskSubLayers() {
        guard let maskLayer = maskLayer else { return }
        self.overlayLayer.addSublayer(maskLayer)
    }
    
    func showBoxes(predictions: YOLOResult) {
        
        let width = self.bounds.width
        let height = self.bounds.height
        let resultCount = predictions.boxes.count
        
        if UIDevice.current.orientation == .portrait {
            var ratio: CGFloat = 1.0
            if videoCapture.captureSession.sessionPreset == .photo {
                ratio = (height / width) / (4.0 / 3.0)
            } else {
                ratio = (height / width) / (16.0 / 9.0)
            }
            
            self.labelSliderNumItems.text = "\(resultCount) items (max \(Int(sliderNumItems.value)))"
            for i in 0..<boundingBoxViews.count {
                if i < resultCount && i < 50 {
                    var rect = CGRect.zero
                    var label = ""
                    var boxColor: UIColor = .white
                    var confidence: CGFloat = 0
                    var alpha: CGFloat = 0.9
                    var bestClass = ""
                    
                    switch task {
                    case .detect:
                        let prediction = predictions.boxes[i]
                        rect = CGRect(x: prediction.xywhn.minX,
                                      y: 1-prediction.xywhn.maxY,
                                      width: prediction.xywhn.width,
                                      height: prediction.xywhn.height)
                        bestClass = prediction.cls
                        confidence = CGFloat(prediction.conf)
                        let colorIndex = prediction.index % ultralyticsColors.count
                        boxColor = colorForClassID(prediction.index)
                        label = String(format: "%@ %.1f", bestClass, confidence * 100)
                        alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
                    default:
                        // segment/poseでも同じ boxes 構造
                        let prediction = predictions.boxes[i]
                        rect = CGRect(x: prediction.xywhn.minX,
                                      y: 1-prediction.xywhn.maxY,
                                      width: prediction.xywhn.width,
                                      height: prediction.xywhn.height)
                        bestClass = prediction.cls
                        confidence = CGFloat(prediction.conf)
                        let colorIndex = prediction.index % ultralyticsColors.count
                        boxColor = colorForClassID(prediction.index)
                        label = String(format: "%@ %.1f", bestClass, confidence * 100)
                        alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
                    }
                    
                    var displayRect = rect
                    switch UIDevice.current.orientation {
                    case .portraitUpsideDown:
                        displayRect = CGRect(
                            x: 1.0 - rect.origin.x - rect.width,
                            y: 1.0 - rect.origin.y - rect.height,
                            width: rect.width,
                            height: rect.height)
                    default: break
                    }
                    if ratio >= 1 {
                        let offset = (1 - ratio) * (0.5 - displayRect.minX)
                        let transform = CGAffineTransform(scaleX: 1, y: -1)
                            .translatedBy(x: offset, y: -1)
                        displayRect = displayRect.applying(transform)
                        displayRect.size.width *= ratio
                    } else {
                        let offset = (ratio - 1) * (0.5 - displayRect.maxY)
                        let transform = CGAffineTransform(scaleX: 1, y: -1)
                            .translatedBy(x: 0, y: offset - 1)
                        displayRect = displayRect.applying(transform)
                        displayRect.size.width *= ratio
                    }
                    displayRect = VNImageRectForNormalizedRect(displayRect, Int(width), Int(height))
                    
                    boundingBoxViews[i].show(
                        frame: displayRect, label: label, color: boxColor, alpha: alpha)
                    
                } else {
                    boundingBoxViews[i].hide()
                }
            }
        }
        else {
            // 横向き
            let frameAspectRatio = videoCapture.longSide / videoCapture.shortSide
            let viewAspectRatio = width / height
            var scaleX: CGFloat = 1.0
            var scaleY: CGFloat = 1.0
            var offsetX: CGFloat = 0.0
            var offsetY: CGFloat = 0.0
            
            if frameAspectRatio > viewAspectRatio {
                scaleY = height / videoCapture.shortSide
                scaleX = scaleY
                offsetX = (videoCapture.longSide * scaleX - width) / 2
            } else {
                scaleX = width / videoCapture.longSide
                scaleY = scaleX
                offsetY = (videoCapture.shortSide * scaleY - height) / 2
            }
            
            for i in 0..<boundingBoxViews.count {
                if i < resultCount && i < 50 {
                    var rect = CGRect.zero
                    var label = ""
                    var boxColor: UIColor = .white
                    var confidence: CGFloat = 0
                    var alpha: CGFloat = 0.9
                    var bestClass = ""
                    
                    switch task {
                    case .detect:
                        let prediction = predictions.boxes[i]
                        rect = CGRect(
                            x: prediction.xywhn.minX,
                            y: 1 - prediction.xywhn.maxY,
                            width: prediction.xywhn.width,
                            height: prediction.xywhn.height
                        )
                        bestClass = prediction.cls
                        confidence = CGFloat(prediction.conf)
                    default:
                        let prediction = predictions.boxes[i]
                        rect = CGRect(
                            x: prediction.xywhn.minX,
                            y: 1 - prediction.xywhn.maxY,
                            width: prediction.xywhn.width,
                            height: prediction.xywhn.height
                        )
                        bestClass = prediction.cls
                        confidence = CGFloat(prediction.conf)
                    }
                    
                    let colorIndex = predictions.boxes[i].index % ultralyticsColors.count
                    boxColor = colorForClassID(predictions.boxes[i].index)
                    label = String(format: "%@ %.1f", bestClass, confidence * 100)
                    alpha = CGFloat((confidence - 0.2) / (1.0 - 0.2) * 0.9)
                    
                    rect.origin.x = rect.origin.x * videoCapture.longSide * scaleX - offsetX
                    rect.origin.y = height - (rect.origin.y * videoCapture.shortSide * scaleY
                                              - offsetY
                                              + rect.size.height * videoCapture.shortSide * scaleY)
                    rect.size.width *= videoCapture.longSide * scaleX
                    rect.size.height *= videoCapture.shortSide * scaleY
                    
                    boundingBoxViews[i].show(
                        frame: rect,
                        label: label,
                        color: boxColor,
                        alpha: alpha
                    )
                } else {
                    boundingBoxViews[i].hide()
                }
            }
        }
    }
    
    func removeClassificationLayers() {
        if let sublayers = self.layer.sublayers {
            for layer in sublayers where layer.name == "YOLOOverlayLayer" {
                layer.removeFromSuperlayer()
            }
        }
    }
    
    func overlayYOLOClassificationsCALayer(on view: UIView, result: YOLOResult) {
        removeClassificationLayers()
        
        let overlayLayer = CALayer()
        overlayLayer.frame = view.bounds
        overlayLayer.name = "YOLOOverlayLayer"
        
        guard let top1 = result.probs?.top1,
              let top1Conf = result.probs?.top1Conf else {
            return
        }
        
        var colorIndex = 0
        if let index = result.names.firstIndex(of: top1) {
            colorIndex = index % ultralyticsColors.count
        }
        let color = ultralyticsColors[colorIndex]
        
        let confidencePercent = round(top1Conf * 1000) / 10
        let labelText = " \(top1) \(confidencePercent)% "
        
        let textLayer = CATextLayer()
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.alignmentMode = .left
        let fontSize = self.bounds.height * 0.02
        textLayer.font = UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        textLayer.fontSize = fontSize
        textLayer.foregroundColor = UIColor.white.cgColor
        textLayer.backgroundColor = color.cgColor
        textLayer.cornerRadius = 4
        textLayer.masksToBounds = true
        
        textLayer.string = labelText
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font : UIFont.systemFont(ofSize: fontSize, weight: .semibold)
        ]
        let textSize = (labelText as NSString).size(withAttributes: textAttributes)
        let width: CGFloat = textSize.width + 10
        let x: CGFloat = self.center.x - (width / 2)
        let y: CGFloat = self.center.y - textSize.height
        let height: CGFloat = textSize.height + 4
        
        textLayer.frame = CGRect(x: x, y: y, width: width, height: height)
        
        overlayLayer.addSublayer(textLayer)
        view.layer.addSublayer(overlayLayer)
    }
    
    private func setupUI() {
        labelName.text = modelName
        labelName.textAlignment = .center
        labelName.font = UIFont.systemFont(ofSize: 24, weight: .medium)
        labelName.textColor = .black
        labelName.font = UIFont.preferredFont(forTextStyle: .title1)
        self.addSubview(labelName)
        
        labelFPS.text = String(format: "%.1f FPS - %.1f ms", 0.0, 0.0)
        labelFPS.textAlignment = .center
        labelFPS.textColor = .black
        labelFPS.font = UIFont.preferredFont(forTextStyle: .body)
        self.addSubview(labelFPS)
        
        labelSliderNumItems.text = "0 items (max 30)"
        labelSliderNumItems.textAlignment = .left
        labelSliderNumItems.textColor = .black
        labelSliderNumItems.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.addSubview(labelSliderNumItems)
        
        sliderNumItems.minimumValue = 0
        sliderNumItems.maximumValue = 100
        sliderNumItems.value = 30
        sliderNumItems.minimumTrackTintColor = .darkGray
        sliderNumItems.maximumTrackTintColor = .systemGray.withAlphaComponent(0.7)
        sliderNumItems.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        self.addSubview(sliderNumItems)
        
        labelSliderConf.text = "0.25 Confidence Threshold"
        labelSliderConf.textAlignment = .left
        labelSliderConf.textColor = .black
        labelSliderConf.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.addSubview(labelSliderConf)
        
        sliderConf.minimumValue = 0
        sliderConf.maximumValue = 1
        sliderConf.value = 0.25
        sliderConf.minimumTrackTintColor = .darkGray
        sliderConf.maximumTrackTintColor = .systemGray.withAlphaComponent(0.7)
        sliderConf.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        self.addSubview(sliderConf)
        
        labelSliderIoU.text = "0.45 IoU Threshold"
        labelSliderIoU.textAlignment = .left
        labelSliderIoU.textColor = .black
        labelSliderIoU.font = UIFont.preferredFont(forTextStyle: .subheadline)
        self.addSubview(labelSliderIoU)
        
        sliderIoU.minimumValue = 0
        sliderIoU.maximumValue = 1
        sliderIoU.value = 0.45
        sliderIoU.minimumTrackTintColor = .darkGray
        sliderIoU.maximumTrackTintColor = .systemGray.withAlphaComponent(0.7)
        sliderIoU.addTarget(self, action: #selector(sliderChanged), for: .valueChanged)
        self.addSubview(sliderIoU)
        
        self.labelSliderNumItems.text = "0 items (max " + String(Int(sliderNumItems.value)) + ")"
        self.labelSliderConf.text = "0.25 Confidence Threshold"
        self.labelSliderIoU.text = "0.45 IoU Threshold"
        
        labelZoom.text = "1.00x"
        labelZoom.textColor = .black
        labelZoom.font = UIFont.systemFont(ofSize: 14)
        labelZoom.textAlignment = .center
        labelZoom.font = UIFont.preferredFont(forTextStyle: .body)
        self.addSubview(labelZoom)
        
        // トラッキングスイッチ
        labelTrackingSwitch.text = "Tracking"
        labelTrackingSwitch.font = UIFont.preferredFont(forTextStyle: .body)
        labelTrackingSwitch.textAlignment = .right
        labelTrackingSwitch.textColor = .black
        self.addSubview(labelTrackingSwitch)
        
        trackingSwitch.isOn = false
        trackingSwitch.addTarget(self, action: #selector(trackingSwitchChanged(_:)), for: .valueChanged)
        self.addSubview(trackingSwitch)
        
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .regular, scale: .default)
        
        playButton.setImage(UIImage(systemName: "play.fill", withConfiguration: config), for: .normal)
        playButton.tintColor = .systemGray
        pauseButton.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        pauseButton.tintColor = .systemGray
        switchCameraButton = UIButton()
        switchCameraButton.setImage(UIImage(systemName: "camera.rotate", withConfiguration: config), for: .normal)
        switchCameraButton.tintColor = .systemGray
        playButton.isEnabled = false
        pauseButton.isEnabled = true
        playButton.addTarget(self, action: #selector(playTapped), for: .touchUpInside)
        pauseButton.addTarget(self, action: #selector(pauseTapped), for: .touchUpInside)
        switchCameraButton.addTarget(self, action: #selector(switchCameraTapped), for: .touchUpInside)
        toolbar.backgroundColor = .darkGray.withAlphaComponent(0.7)
        self.addSubview(toolbar)
        toolbar.addSubview(playButton)
        toolbar.addSubview(pauseButton)
        toolbar.addSubview(switchCameraButton)
        
        self.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch)))
    }
    
    @objc func trackingSwitchChanged(_ sender: UISwitch) {
        isTrackingOn = sender.isOn
    }
    
    public override func layoutSubviews() {
        setupOverlayLayer()
        let isLandscape = bounds.width > bounds.height
        activityIndicator.frame = CGRect(x: center.x - 50, y: center.y - 50, width: 100, height: 100)
        
        if isLandscape {
            toolbar.backgroundColor = .clear
            playButton.tintColor = .darkGray
            pauseButton.tintColor = .darkGray
            switchCameraButton.tintColor = .darkGray
            
            let width = bounds.width
            let height = bounds.height
            
            let topMargin: CGFloat = 0
            let titleLabelHeight: CGFloat = height * 0.1
            labelName.frame = CGRect(
                x: 0,
                y: topMargin,
                width: width,
                height: titleLabelHeight
            )
            
            let subLabelHeight: CGFloat = height * 0.04
            labelFPS.frame = CGRect(
                x: 0,
                y: center.y - height * 0.24 - subLabelHeight,
                width: width,
                height: subLabelHeight
            )
            
            let sliderWidth: CGFloat = width * 0.2
            let sliderHeight: CGFloat = height * 0.1
            
            labelSliderNumItems.frame = CGRect(
                x: width * 0.1,
                y: labelFPS.frame.minY - sliderHeight,
                width: sliderWidth,
                height: sliderHeight
            )
            
            sliderNumItems.frame = CGRect(
                x: width * 0.1,
                y: labelSliderNumItems.frame.maxY + 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            labelSliderConf.frame = CGRect(
                x: width * 0.1,
                y: sliderNumItems.frame.maxY + 10,
                width: sliderWidth * 1.5,
                height: sliderHeight
            )
            
            sliderConf.frame = CGRect(
                x: width * 0.1,
                y: labelSliderConf.frame.maxY + 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            labelSliderIoU.frame = CGRect(
                x: width * 0.1,
                y: sliderConf.frame.maxY + 10,
                width: sliderWidth * 1.5,
                height: sliderHeight
            )
            
            sliderIoU.frame = CGRect(
                x: width * 0.1,
                y: labelSliderIoU.frame.maxY + 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            // トラッキングスイッチを labelSliderConf と同じ高さで右寄せ
            labelTrackingSwitch.frame = CGRect(
                x: width - sliderWidth * 1.2,
                y: labelSliderConf.frame.minY,
                width: sliderWidth * 1.0,
                height: sliderHeight
            )
            trackingSwitch.frame = CGRect(
                x: width - sliderWidth * 0.3,
                y: labelTrackingSwitch.frame.maxY + 5,
                width: 60,
                height: 31
            )
            
            let zoomLabelWidth: CGFloat = width * 0.2
            labelZoom.frame = CGRect(
                x: center.x - zoomLabelWidth / 2,
                y: self.bounds.maxY - 120,
                width: zoomLabelWidth,
                height: height * 0.03
            )
            
            let toolBarHeight: CGFloat = 66
            let buttonHeihgt: CGFloat = toolBarHeight * 0.75
            toolbar.frame = CGRect(x: 0, y: height - toolBarHeight, width: width, height: toolBarHeight)
            playButton.frame = CGRect(x: 0, y: 0, width: buttonHeihgt, height: buttonHeihgt)
            pauseButton.frame = CGRect(x: playButton.frame.maxX, y: 0, width: buttonHeihgt, height: buttonHeihgt)
            switchCameraButton.frame = CGRect(x: pauseButton.frame.maxX, y: 0, width: buttonHeihgt, height: buttonHeihgt)
        } else {
            // ポートレート
            toolbar.backgroundColor = .darkGray.withAlphaComponent(0.7)
            playButton.tintColor = .systemGray
            pauseButton.tintColor = .systemGray
            switchCameraButton.tintColor = .systemGray
            
            let width = bounds.width
            let height = bounds.height
            
            let topMargin: CGFloat = height * 0.02
            let titleLabelHeight: CGFloat = height * 0.1
            labelName.frame = CGRect(
                x: 0,
                y: topMargin,
                width: width,
                height: titleLabelHeight
            )
            
            let subLabelHeight: CGFloat = height * 0.04
            labelFPS.frame = CGRect(
                x: 0,
                y: labelName.frame.maxY + 15,
                width: width,
                height: subLabelHeight
            )
            
            let sliderWidth: CGFloat = width * 0.46
            let sliderHeight: CGFloat = height * 0.02
            
            sliderNumItems.frame = CGRect(
                x: width * 0.01,
                y: center.y - sliderHeight - height * 0.24,
                width: sliderWidth,
                height: sliderHeight
            )
            labelSliderNumItems.frame = CGRect(
                x: width * 0.01,
                y: sliderNumItems.frame.minY - sliderHeight - 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            labelSliderConf.frame = CGRect(
                x: width * 0.01,
                y: center.y + height * 0.24,
                width: sliderWidth * 1.5,
                height: sliderHeight
            )
            sliderConf.frame = CGRect(
                x: width * 0.01,
                y: labelSliderConf.frame.maxY + 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            labelSliderIoU.frame = CGRect(
                x: width * 0.01,
                y: sliderConf.frame.maxY + 10,
                width: sliderWidth * 1.5,
                height: sliderHeight
            )
            sliderIoU.frame = CGRect(
                x: width * 0.01,
                y: labelSliderIoU.frame.maxY + 10,
                width: sliderWidth,
                height: sliderHeight
            )
            
            // トラッキングスイッチを labelSliderConf と同じ高さで右寄せ
            let switchWidth: CGFloat = 60
            let switchHeight: CGFloat = 31
            labelTrackingSwitch.frame = CGRect(
                x: width - sliderWidth * 0.9,
                y: labelSliderConf.frame.minY,
                width: sliderWidth * 0.8,
                height: sliderHeight
            )
            trackingSwitch.frame = CGRect(
                x: width - switchWidth - 10,
                y: labelTrackingSwitch.frame.maxY + 5,
                width: switchWidth,
                height: switchHeight
            )
            
            let zoomLabelWidth: CGFloat = width * 0.2
            labelZoom.frame = CGRect(
                x: center.x - zoomLabelWidth / 2,
                y: self.bounds.maxY - 120,
                width: zoomLabelWidth,
                height: height * 0.03
            )
            
            let toolBarHeight: CGFloat = 66
            let buttonHeihgt: CGFloat = toolBarHeight * 0.75
            toolbar.frame = CGRect(x: 0, y: height - toolBarHeight, width: width, height: toolBarHeight)
            playButton.frame = CGRect(x: 0, y: 0, width: buttonHeihgt, height: buttonHeihgt)
            pauseButton.frame = CGRect(x: playButton.frame.maxX, y: 0, width: buttonHeihgt, height: buttonHeihgt)
            switchCameraButton.frame = CGRect(x: pauseButton.frame.maxX, y: 0, width: buttonHeihgt, height: buttonHeihgt)
        }
        
        self.videoCapture.previewLayer?.frame = self.bounds
    }
    
    private func setUpOrientationChangeNotification() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(orientationDidChange),
            name: UIDevice.orientationDidChangeNotification, object: nil)
    }
    
    @objc func orientationDidChange() {
        var orientation: AVCaptureVideoOrientation = .portrait
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = .portrait
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        case .landscapeRight:
            orientation = .landscapeLeft
        case .landscapeLeft:
            orientation = .landscapeRight
        default:
            return
        }
        videoCapture.updateVideoOrientation(orientation:orientation)
    }
    
    @objc func sliderChanged(_ sender: Any) {
        if sender as? UISlider === sliderNumItems {
            if let detector = videoCapture.predictor as? ObjectDetector {
                let numItems = Int(sliderNumItems.value)
                detector.setNumItemsThreshold(numItems: numItems)
            }
        }
        let conf = Double(round(100 * sliderConf.value)) / 100
        let iou = Double(round(100 * sliderIoU.value)) / 100
        self.labelSliderConf.text = String(conf) + " Confidence Threshold"
        self.labelSliderIoU.text = String(iou) + " IoU Threshold"
        
        if let detector = videoCapture.predictor as? ObjectDetector {
            detector.setIouThreshold(iou: iou)
            detector.setConfidenceThreshold(confidence: conf)
        }
    }
    
    @objc func pinch(_ pinch: UIPinchGestureRecognizer) {
        guard let device = videoCapture.captureDevice else { return }
        
        func minMaxZoom(_ factor: CGFloat) -> CGFloat {
            return min(min(max(factor, minimumZoom), maximumZoom), device.activeFormat.videoMaxZoomFactor)
        }
        
        func update(scale factor: CGFloat) {
            do {
                try device.lockForConfiguration()
                defer {
                    device.unlockForConfiguration()
                }
                device.videoZoomFactor = factor
            } catch {
                print("\(error.localizedDescription)")
            }
        }
        
        let newScaleFactor = minMaxZoom(pinch.scale * lastZoomFactor)
        switch pinch.state {
        case .began, .changed:
            update(scale: newScaleFactor)
            self.labelZoom.text = String(format: "%.2fx", newScaleFactor)
            self.labelZoom.font = UIFont.preferredFont(forTextStyle: .title2)
        case .ended:
            lastZoomFactor = minMaxZoom(newScaleFactor)
            update(scale: lastZoomFactor)
            self.labelZoom.font = UIFont.preferredFont(forTextStyle: .body)
        default: break
        }
    }
    
    @objc func playTapped() {
        selection.selectionChanged()
        self.videoCapture.start()
        playButton.isEnabled = false
        pauseButton.isEnabled = true
    }
    
    @objc func pauseTapped() {
        selection.selectionChanged()
        self.videoCapture.stop()
        playButton.isEnabled = true
        pauseButton.isEnabled = false
    }
    
    @objc func switchCameraTapped() {
        
        self.videoCapture.captureSession.beginConfiguration()
        let currentInput = self.videoCapture.captureSession.inputs.first as? AVCaptureDeviceInput
        self.videoCapture.captureSession.removeInput(currentInput!)
        guard let currentPosition = currentInput?.device.position else { return }
        
        let nextCameraPosition: AVCaptureDevice.Position = currentPosition == .back ? .front : .back
        
        let newCameraDevice = bestCaptureDevice(position: nextCameraPosition)
        
        guard let videoInput1 = try? AVCaptureDeviceInput(device: newCameraDevice) else {
            return
        }
        
        self.videoCapture.captureSession.addInput(videoInput1)
        var orientation: AVCaptureVideoOrientation = .portrait
        switch UIDevice.current.orientation {
        case .portrait:
            orientation = .portrait
        case .portraitUpsideDown:
            orientation = .portraitUpsideDown
        case .landscapeRight:
            orientation = .landscapeLeft
        case .landscapeLeft:
            orientation = .landscapeRight
        default:
            return
        }
        self.videoCapture.updateVideoOrientation(orientation: orientation)
        
        self.videoCapture.captureSession.commitConfiguration()
    }
    
    public func capturePhoto(completion: @escaping (UIImage?) -> Void) {
        self.photoCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()
        usleep(20_000)  // short delay to allow camera to focus
        self.videoCapture.photoOutput.capturePhoto(
            with: settings, delegate: self as AVCapturePhotoCaptureDelegate
        )
    }
    
    public func setInferenceFlag(ok: Bool) {
        videoCapture.inferenceOK = ok
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension YOLOView: @preconcurrency AVCapturePhotoCaptureDelegate {
    public func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        if let error = error {
            print("error occurred : \(error.localizedDescription)")
        }
        if let dataImage = photo.fileDataRepresentation() {
            let dataProvider = CGDataProvider(data: dataImage as CFData)
            let cgImageRef: CGImage! = CGImage(
                jpegDataProviderSource: dataProvider!, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent)
            var isCameraFront = false
            if let currentInput = self.videoCapture.captureSession.inputs.first as? AVCaptureDeviceInput,
               currentInput.device.position == .front
            {
                isCameraFront = true
            }
            var orientation: CGImagePropertyOrientation = isCameraFront ? .leftMirrored : .right
            switch UIDevice.current.orientation {
            case .landscapeLeft:
                orientation = isCameraFront ? .downMirrored : .up
            case .landscapeRight:
                orientation = isCameraFront ? .upMirrored : .down
            default:
                break
            }
            var image = UIImage(cgImage: cgImageRef, scale: 0.5, orientation: .right)
            if let orientedCIImage = CIImage(image: image)?.oriented(orientation),
               let cgImage = CIContext().createCGImage(orientedCIImage, from: orientedCIImage.extent)
            {
                image = UIImage(cgImage: cgImage)
            }
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.frame = self.frame
            let imageLayer = imageView.layer
            self.layer.insertSublayer(imageLayer, above: videoCapture.previewLayer)
            
            var tempViews = [UIView]()
            let boundingBoxInfos = makeBoundingBoxInfos(from: boundingBoxViews)
            for info in boundingBoxInfos where !info.isHidden {
                let boxView = createBoxView(from: info)
                boxView.frame = info.rect
                self.addSubview(boxView)
                tempViews.append(boxView)
            }
            let bounds = UIScreen.main.bounds
            UIGraphicsBeginImageContextWithOptions(bounds.size, true, 0.0)
            self.drawHierarchy(in: bounds, afterScreenUpdates: true)
            let img = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            imageLayer.removeFromSuperlayer()
            for v in tempViews {
                v.removeFromSuperview()
            }
            photoCaptureCompletion?(img)
            photoCaptureCompletion = nil
        } else {
            print("AVCapturePhotoCaptureDelegate Error")
        }
    }
}
