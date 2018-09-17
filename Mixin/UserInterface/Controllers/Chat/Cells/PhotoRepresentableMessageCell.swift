import UIKit
import SDWebImage
import YYImage

class PhotoRepresentableMessageCell: DetailInfoMessageCell {
    
    let contentImageView = VerticalPositioningImageView()
    let shadowImageView = UIImageView()
    
    lazy var selectedOverlapView: UIView = {
        let view = SelectedOverlapView()
        view.alpha = 0
        contentView.addSubview(view)
        return view
    }()
    
    internal lazy var statusViews = [
        shadowImageView,
        timeLabel,
        statusImageView
    ]
    
    override var contentFrame: CGRect {
        return contentImageView.frame
    }

    override func render(viewModel: MessageViewModel) {
        super.render(viewModel: viewModel)
        if let viewModel = viewModel as? PhotoRepresentableMessageViewModel {
            contentImageView.position = viewModel.layoutPosition
            contentImageView.frame = viewModel.contentFrame
            selectedOverlapView.frame = contentImageView.bounds

            shadowImageView.image = viewModel.shadowImage
            shadowImageView.frame = CGRect(origin: viewModel.shadowImageOrigin,
                                           size: viewModel.shadowImage?.size ?? .zero)
        }
    }
    
    override func prepare() {
        contentImageView.contentMode = .scaleAspectFill
        contentImageView.clipsToBounds = true
        contentImageView.layer.cornerRadius = 6
        contentView.addSubview(contentImageView)
        shadowImageView.contentMode = .scaleToFill
        shadowImageView.layer.cornerRadius = 6
        shadowImageView.clipsToBounds = true
        contentView.addSubview(shadowImageView)
        timeLabel.textColor = .white
        updateAppearance(highlight: false, animated: false)
        contentImageView.addSubview(selectedOverlapView)
        super.prepare()
        backgroundImageView.removeFromSuperview()
        contentImageView.layer.mask = backgroundImageView.layer
    }
    
    override func updateAppearance(highlight: Bool, animated: Bool) {
        UIView.animate(withDuration: animated ? highlightAnimationDuration : 0) {
            self.selectedOverlapView.alpha = highlight ? 1 : 0
        }
    }
    
    func statusSnapshot() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(contentFrame.size, false, UIScreen.main.scale)
        if let context = UIGraphicsGetCurrentContext() {
            for view in statusViews {
                let origin = view.convert(CGPoint.zero, to: contentImageView)
                context.saveGState()
                context.translateBy(x: origin.x, y: origin.y)
                view.layer.render(in: context)
                context.restoreGState()
            }
        }
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image
    }
    
}

extension PhotoRepresentableMessageCell {

    class SelectedOverlapView: UIView {

        override var backgroundColor: UIColor? {
            set {

            }
            get {
                return super.backgroundColor
            }
        }
        
        private let dimmingColor = UIColor.black.withAlphaComponent(0.2)
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            super.backgroundColor = dimmingColor
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            super.backgroundColor = dimmingColor
        }

    }
    
    class VerticalPositioningImageView: UIView {
        
        enum Position {
            case relativeOffset(CGFloat)
            case center
        }
        
        let imageView = YYAnimatedImageView()

        var position = Position.center {
            didSet {
                setNeedsLayout()
            }
        }
        
        var image: UIImage? {
            get {
                return imageView.image
            }
            set {
                aspectRatio = newValue?.size ?? .zero
                imageView.image = newValue
                setNeedsLayout()
            }
        }
        
        var aspectRatio = CGSize.zero
        
        required init?(coder aDecoder: NSCoder) {
            super.init(coder: aDecoder)
            prepare()
        }
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            prepare()
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            if aspectRatio.width <= 1 {
                aspectRatio = CGSize(width: 1, height: 1)
            }
            imageView.frame.size = CGSize(width: bounds.width, height: bounds.width * aspectRatio.height / aspectRatio.width)
            switch position {
            case .center:
                imageView.center = CGPoint(x: bounds.width / 2, y: bounds.height / 2)
            case .relativeOffset(let offset):
                let y = offset * imageView.bounds.size.height
                imageView.frame.origin = CGPoint(x: 0, y: y)
            }
        }
        
        func setImage(with url: URL, ratio: CGSize) {
            imageView.sd_setImage(with: url, completed: nil)
            aspectRatio = ratio
            setNeedsLayout()
        }
        
        func cancelCurrentImageLoad() {
            imageView.sd_cancelCurrentImageLoad()
        }
        
        private func prepare() {
            addSubview(imageView)
            imageView.contentMode = .scaleToFill
            clipsToBounds = true
        }
        
    }

}

