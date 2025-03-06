//  Ultralytics YOLO 🚀 - AGPL-3.0 License
//
//  BoundingBoxView for Ultralytics YOLO App
//  This class is designed to visualize bounding boxes and labels for detected objects in the YOLOv8 models within the Ultralytics YOLO app.
//  It leverages Core Animation layers to draw the bounding boxes and text labels dynamically on the detection video feed.
//  Licensed under AGPL-3.0. For commercial use, refer to Ultralytics licensing: https://ultralytics.com/license
//  Access the source code: https://github.com/ultralytics/yolo-ios-app
//
//  BoundingBoxView facilitates the clear representation of detection results, improving user interaction with the app by
//  providing immediate visual feedback on detected objects, including their classification and confidence level.

import Foundation
import UIKit

/// Manages the visualization of bounding boxes and associated labels for object detection results.
@MainActor
class BoundingBoxView {
    /// バウンディングボックス用のshapeLayer
    let shapeLayer: CAShapeLayer
    /// ラベル（テキスト）用のtextLayer
    let textLayer: CATextLayer
    
    /// iPhone 13 / 13 Pro (幅 390pt) を基準にした値
    private let baseScreenWidth: CGFloat = 390
    
    /// iPhone 13 Proで最適だったlineWidth, fontSize
    private let baseLineWidth: CGFloat = 4.0
    private let baseFontSize: CGFloat = 14.0
    
    init() {
        shapeLayer = CAShapeLayer()
        shapeLayer.fillColor = UIColor.clear.cgColor
        shapeLayer.lineWidth = baseLineWidth
        shapeLayer.isHidden = true
        
        textLayer = CATextLayer()
        textLayer.isHidden = true
        textLayer.contentsScale = UIScreen.main.scale
        
        // ここでは初期値として、あとで上書きする
        textLayer.fontSize = baseFontSize
        textLayer.font = UIFont(name: "Avenir", size: baseFontSize)
        textLayer.alignmentMode = .center
    }
    
    func addToLayer(_ parent: CALayer) {
        parent.addSublayer(shapeLayer)
        parent.addSublayer(textLayer)
    }
    
    /// 親ビューのサイズを受け取り、lineWidth とフォントサイズをスケーリングして描画
    ///
    /// - Parameters:
    ///   - frame: バウンディングボックス矩形
    ///   - label: ラベル文字列
    ///   - color: バウンディング枠線＋ラベル背景のカラー
    ///   - alpha: 透明度
    ///   - parentViewSize: 親ビューサイズ（例: `superview.bounds.size`）
    func show(
        frame: CGRect,
        label: String,
        color: UIColor,
        alpha: CGFloat,
        parentViewSize: CGSize
    ) {
        CATransaction.setDisableActions(true)
        
        // 画面幅に応じたスケーリング係数
        let scale = parentViewSize.width / baseScreenWidth
        
        // 1) バウンディングボックス線の太さをスケーリング
        shapeLayer.lineWidth = baseLineWidth * scale
        shapeLayer.strokeColor = color.withAlphaComponent(alpha).cgColor
        shapeLayer.isHidden = false
        
        // 2) 文字サイズをスケーリング
        //   CATextLayer の fontSize をスケーリング
        textLayer.fontSize = baseFontSize * scale
        
        //   フォントオブジェクト自体を作り直す場合
        textLayer.font = UIFont(name: "Avenir", size: textLayer.fontSize)
        
        textLayer.foregroundColor = UIColor.white.withAlphaComponent(alpha).cgColor
        textLayer.backgroundColor = color.withAlphaComponent(alpha).cgColor
        textLayer.isHidden = false
        
        // 3) バウンディングボックスパスを設定
        let path = UIBezierPath(roundedRect: frame, cornerRadius: 6.0)
        shapeLayer.path = path.cgPath
        
        // 4) テキスト
        textLayer.string = label
        
        // テキストのサイズ測定
        // textLayer.font は CFType なので、`label.boundingRect` のフォント属性に使う場合は
        // UIFontを別途用意する。ここでは textLayer.fontSize を読んで UIFont を生成
        let scaledFont = UIFont(name: "Avenir", size: textLayer.fontSize)
        let attributes = [NSAttributedString.Key.font: scaledFont as Any]
        
        let textRect = label.boundingRect(
            with: CGSize(width: 400, height: 100),
            options: .truncatesLastVisibleLine,
            attributes: attributes,
            context: nil
        )
        // 少しパディングを加える
        let textSize = CGSize(width: textRect.width + 12, height: textRect.height)
        let textOrigin = CGPoint(
            x: frame.origin.x - 2,
            y: frame.origin.y - textSize.height - 2
        )
        textLayer.frame = CGRect(origin: textOrigin, size: textSize)
    }
    
    func hide() {
        shapeLayer.isHidden = true
        textLayer.isHidden = true
    }
}


struct BoundingBoxInfo {
    var rect: CGRect
    var strokeColor: UIColor
    var strokeWidth: CGFloat
    var cornerRadius: CGFloat
    var alpha: CGFloat
    var labelText: String
    var labelFont: UIFont
    var labelTextColor: UIColor
    var labelBackgroundColor: UIColor
    var isHidden: Bool
}

@MainActor
func createBoxView(from info: BoundingBoxInfo) -> UIView {
    let boxView = UIView()
    boxView.layer.borderColor = info.strokeColor.withAlphaComponent(info.alpha).cgColor
    boxView.layer.borderWidth = info.strokeWidth
    boxView.layer.cornerRadius = info.cornerRadius
    boxView.backgroundColor = .clear
    
    let label = UILabel()
    label.text = info.labelText
    label.font = info.labelFont
    label.textColor = info.labelTextColor.withAlphaComponent(info.alpha)
    label.backgroundColor = info.labelBackgroundColor.withAlphaComponent(info.alpha)
    label.sizeToFit()
    
    let labelHeight = label.bounds.height
    label.frame.origin = CGPoint(x: 0, y: -labelHeight - 4)
    label.frame.size.width = max(label.frame.size.width, boxView.bounds.width)
    
    boxView.addSubview(label)
    
    return boxView
}

@MainActor
func makeBoundingBoxInfos(from boxViews: [BoundingBoxView]) -> [BoundingBoxInfo] {
    var results = [BoundingBoxInfo]()
    
    for box in boxViews {
        let shapeLayer = box.shapeLayer
        let textLayer = box.textLayer
        
        let hidden = (shapeLayer.isHidden && textLayer.isHidden)
        if !hidden {
            // 1) バウンディングボックスのCGRect（shapeLayer.path から取得）
            //    shapeLayer.path が nil であれば .zero とする
            let boundingRect: CGRect
            if let path = shapeLayer.path {
                boundingRect = path.boundingBox
            } else {
                boundingRect = .zero
            }
            
            // 2) 枠線色・透明度
            let strokeCGColor = shapeLayer.strokeColor ?? UIColor.clear.cgColor
            let strokeUI = UIColor(cgColor: strokeCGColor)
            // strokeUI から alphaを抜き出す（strokeUI.cgColor.alpha でもOK）
            let strokeAlpha = strokeUI.cgColor.alpha
            
            // 3) ライン幅
            let lineWidth = shapeLayer.lineWidth
            
            // 4) 角丸 (BoundingBoxViewで固定値 6.0 を使っているため、合わせる)
            let cornerRadius: CGFloat = 6.0
            
            // 5) テキストレイヤーからラベル文字を取得
            let labelString = (textLayer.string as? String) ?? ""
            
            // テキストレイヤーの backgroundColor
            let labelBGCG = textLayer.backgroundColor ?? UIColor.clear.cgColor
            let labelBG = UIColor(cgColor: labelBGCG)
            
            // テキストの前景色
            let fgCG = textLayer.foregroundColor ?? UIColor.white.cgColor
            let labelTextColor = UIColor(cgColor: fgCG)
            
            let fontSize = textLayer.fontSize
            let fontName = "Avenir"
            let labelFont = UIFont(name: fontName, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize)
            
            let finalAlpha = strokeAlpha  // shapeLayerベース
            
            let info = BoundingBoxInfo(
                rect: boundingRect,
                strokeColor: strokeUI.withAlphaComponent(finalAlpha),
                strokeWidth: lineWidth,
                cornerRadius: cornerRadius,
                alpha: finalAlpha,
                labelText: labelString,
                labelFont: labelFont,
                labelTextColor: labelTextColor.withAlphaComponent(finalAlpha),
                labelBackgroundColor: labelBG.withAlphaComponent(finalAlpha),
                isHidden: hidden
            )
            results.append(info)
        }
    }
    
    return results
        
}
