//
//  BasestationTableViewCell.swift
//  BaseStation Manager
//
//  Created by Jordan Koch on 11/27/23.
//

import UIKit

class BasestationTableViewCell: UITableViewCell {
    
    private var blinkingView: UIView?
    private let circleSize: CGFloat = 10

    func configureForState(_ state: DeviceState) {
        accessoryView?.removeFromSuperview()

        let circleView = createCircleView()
        circleView.backgroundColor = colorForState(state)

        switch state {
            case .booting, .identifying:
                startBlinking(view: circleView)
                accessoryView = circleView

            case .unknown:
                let activityIndicator = UIActivityIndicatorView(style: .medium)
                activityIndicator.startAnimating()
                accessoryView = activityIndicator

            default:
                circleView.layer.removeAllAnimations()
                accessoryView = circleView
        }
    }
    
    private func colorForState(_ state: DeviceState) -> UIColor {
        switch state {
            case .on:
                return .green
            case .off, .booting:
                return .blue
            case .powering, .identifying:
                return .white
            case .error:
                return .red
            case .unknown:
                return .gray
        }
    }

    private func createCircleView() -> UIView {
        let circleView = UIView(frame: CGRect(x: 0, y: 0, width: circleSize, height: circleSize))
        circleView.layer.cornerRadius = circleSize / 2
        return circleView
    }

    private func startBlinking(view: UIView) {
        view.alpha = 1.0
        blinkingView = view

        // Using a key to uniquely identify the animation
        let blinkingAnimationKey = "blinkingAnimation"
        
        // Remove any existing blinking animation
        view.layer.removeAnimation(forKey: blinkingAnimationKey)

        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = 1.0
        animation.toValue = 0.0
        animation.duration = 0.26
        animation.timingFunction = CAMediaTimingFunction(name: .default)
        animation.autoreverses = true
        animation.repeatCount = .infinity

        view.layer.add(animation, forKey: blinkingAnimationKey)
    }
    
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil, let blinkingView = blinkingView {
            // Resume blinking animation if it was stopped
            startBlinking(view: blinkingView)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        blinkingView?.layer.removeAnimation(forKey: "blinkingAnimation")
        blinkingView = nil
    }
    
}
