import UIKit
import SDWebImage

class PhotoMessageCell: PhotoRepresentableMessageCell, AttachmentExpirationHintingMessageCell {
    
    weak var attachmentLoadingDelegate: AttachmentLoadingMessageCellDelegate?

    let operationButton: NetworkOperationButton! = NetworkOperationButton(type: .custom)
    let expiredHintLabel = UILabel()
    
    override func prepareForReuse() {
        super.prepareForReuse()
        contentImageView.sd_cancelCurrentImageLoad()
    }

    override func prepare() {
        super.prepare()
        prepareOperationButtonAndExpiredHintLabel()
        operationButton.addTarget(self, action: #selector(networkOperationAction(_:)), for: .touchUpInside)
    }
    
    override func render(viewModel: MessageViewModel) {
        super.render(viewModel: viewModel)
        if let viewModel = viewModel as? PhotoMessageViewModel {
            updateOperationButtonAndExpiredHintLabel()
            if let mediaUrl = viewModel.message.mediaUrl, !mediaUrl.isEmpty {
                let url = MixinFile.url(ofChatDirectory: .photos, filename: mediaUrl)
                contentImageView.setImage(with: url, ratio: viewModel.aspectRatio)
            } else {
                contentImageView.image = viewModel.thumbnail
            }
        }
    }
    
    @objc func networkOperationAction(_ sender: Any) {
        attachmentLoadingDelegate?.attachmentLoadingCellDidSelectNetworkOperation(self)
    }
    
}
