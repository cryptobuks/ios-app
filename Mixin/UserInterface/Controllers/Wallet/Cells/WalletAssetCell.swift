import UIKit

class WalletAssetCell: UITableViewCell {
    
    static let height: CGFloat = 90
    
    @IBOutlet weak var cardView: ShadowedCardView!
    @IBOutlet weak var iconImageView: CornerImageView!
    @IBOutlet weak var chainImageView: CornerImageView!
    @IBOutlet weak var balanceLabel: UILabel!
    @IBOutlet weak var symbolLabel: UILabel!
    @IBOutlet weak var changeLabel: UILabel!
    @IBOutlet weak var usdPriceLabel: UILabel!
    @IBOutlet weak var usdBalanceLabel: UILabel!
    @IBOutlet weak var noUSDPriceIndicatorLabel: UILabel!
    
    override func prepareForReuse() {
        super.prepareForReuse()
        iconImageView.sd_cancelCurrentImageLoad()
        chainImageView.sd_cancelCurrentImageLoad()
    }
    
    override func setSelected(_ selected: Bool, animated: Bool) {
        super.setSelected(selected, animated: animated)
        cardView.setHighlighted(selected, animated: animated)
    }
    
    override func setHighlighted(_ highlighted: Bool, animated: Bool) {
        super.setHighlighted(highlighted, animated: animated)
        cardView.setHighlighted(highlighted, animated: animated)
    }
    
    func render(asset: AssetItem) {
        iconImageView.sd_setImage(with: URL(string: asset.iconUrl), placeholderImage: #imageLiteral(resourceName: "ic_place_holder"))
        if let chainIconUrl = asset.chainIconUrl {
            chainImageView.sd_setImage(with: URL(string: chainIconUrl))
            chainImageView.isHidden = false
        } else {
            chainImageView.isHidden = true
        }
        balanceLabel.text = CurrencyFormatter.localizedString(from: asset.balance, format: .pretty, sign: .never)
        symbolLabel.text = asset.symbol
        if asset.priceUsd.doubleValue > 0 {
            changeLabel.text = " \(asset.localizedUSDChange)%"
            if asset.changeUsd.doubleValue > 0 {
                changeLabel.textColor = .walletGreen
            } else {
                changeLabel.textColor = .walletRed
            }
            usdPriceLabel.text = "$\(asset.localizedPriceUsd)"
            changeLabel.alpha = 1
            usdPriceLabel.alpha = 1
            noUSDPriceIndicatorLabel.alpha = 0
        } else {
            changeLabel.text = Localized.WALLET_NO_PRICE // Just for layout guidance
            usdPriceLabel.text = nil
            changeLabel.alpha = 0
            usdPriceLabel.alpha = 0
            noUSDPriceIndicatorLabel.alpha = 1
        }
        usdBalanceLabel.text = asset.localizedUSDBalance
    }

}
