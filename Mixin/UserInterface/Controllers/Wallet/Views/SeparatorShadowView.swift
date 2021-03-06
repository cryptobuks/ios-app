import UIKit

class SeparatorShadowView: UIView {
    
    let shadowProviderLayer = CALayer()
    
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
        let height: CGFloat = 10
        shadowProviderLayer.frame = CGRect(x: 0, y: -10, width: bounds.width, height: height)
    }
    
    private func prepare() {
        clipsToBounds = true
        layer.addSublayer(shadowProviderLayer)
        shadowProviderLayer.backgroundColor = UIColor.red.cgColor
        shadowProviderLayer.shadowColor = UIColor(rgbValue: 0xC3C3C3).cgColor
        shadowProviderLayer.shadowOpacity = 0.2
        shadowProviderLayer.shadowOffset = CGSize(width: 0, height: 2)
        shadowProviderLayer.shadowRadius = 5
    }
    
}
