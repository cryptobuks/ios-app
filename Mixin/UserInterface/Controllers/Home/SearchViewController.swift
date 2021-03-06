import UIKit

class SearchViewController: UIViewController {

    @IBOutlet weak var keywordTextField: UITextField!
    @IBOutlet weak var cancelButton: UIButton!
    @IBOutlet weak var tableView: UITableView!
    
    @IBOutlet weak var navigationBarContentHeightConstraint: NSLayoutConstraint!
    
    @IBOutlet var beforePresentingConstraints: [NSLayoutConstraint]!
    @IBOutlet var afterPresentingConstraints: [NSLayoutConstraint]!
    
    private let searchImageView = UIImageView(image: #imageLiteral(resourceName: "ic_search"))
    private let headerReuseId = "SearchSectionHeader"
    private let contactCellReuseId = "ContactCell"
    private let conversationCellReuseId = "ConversationCell"
    private let headerHeight: CGFloat = 28
    
    private var allContacts = [UserItem]()
    private var users = [UserItem]()
    private var assets = [AssetItem]()
    private var conversations = [ConversationItem]()
    private var searchQueue = OperationQueue()
    private var contactsLoadingQueue = OperationQueue()
    private var isPresenting = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
        searchQueue.maxConcurrentOperationCount = 1
        contactsLoadingQueue.maxConcurrentOperationCount = 1
        tableView.register(GeneralTableViewHeader.self, forHeaderFooterViewReuseIdentifier: headerReuseId)
        tableView.register(UINib(nibName: "SearchResultContactCell", bundle: .main), forCellReuseIdentifier: contactCellReuseId)
        tableView.register(UINib(nibName: "ConversationCell", bundle: .main), forCellReuseIdentifier: conversationCellReuseId)
        tableView.register(UINib(nibName: "SearchResultAssetCell", bundle: .main), forCellReuseIdentifier: SearchResultAssetCell.cellIdentifier)
        tableView.tableFooterView = UIView()
        tableView.contentInset.top = navigationBarContentHeightConstraint.constant
        tableView.dataSource = self
        tableView.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(contactsDidChange(_:)), name: .ContactsDidChange, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @IBAction func searchAction(_ sender: Any) {
        let keyword = self.keyword
        searchQueue.cancelAllOperations()
        if keyword.isEmpty {
            self.assets = []
            self.users = []
            self.conversations = []
            showContacts()
        } else {
            tableView.reloadData()
            let op = BlockOperation()
            op.addExecutionBlock { [unowned op] in
                guard !op.isCancelled else {
                    return
                }
                let assets = AssetDAO.shared.searchAssets(content: keyword)
                let users = UserDAO.shared.getUsers(nameOrPhone: keyword)
                let messages = ConversationDAO.shared.searchConversation(content: keyword)
                DispatchQueue.main.sync {
                    guard !op.isCancelled else {
                        return
                    }
                    self.assets = assets
                    self.users = users
                    self.conversations = messages
                    self.tableView.reloadData()
                }
            }
            searchQueue.addOperation(op)
        }
    }

    func prepare() {
        reloadContacts()
    }
    
    func present() {
        prepareForReuse()
        isPresenting = true
        beforePresentingConstraints.forEach {
            $0.priority = .defaultLow
        }
        afterPresentingConstraints.forEach {
            $0.priority = .defaultHigh
        }
        showContacts()
        keywordTextField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        UIView.animate(withDuration: 0.3, animations: {
            self.view.layoutIfNeeded()
        }) { (_) in
            self.keywordTextField.becomeFirstResponder()
        }
    }
    
    func dismiss() {
        isPresenting = false
        keywordTextField.resignFirstResponder()
        searchQueue.cancelAllOperations()
        contactsLoadingQueue.cancelAllOperations()
    }
    
    @objc func contactsDidChange(_ notification: Notification) {
        reloadContacts()
    }
    
    class func instance() -> SearchViewController {
        return Storyboard.home.instantiateViewController(withIdentifier: "search") as! SearchViewController
    }
    
    private var keyword: String {
        return keywordTextField.text ?? ""
    }
    
    private func reloadContacts() {
        contactsLoadingQueue.cancelAllOperations()
        contactsLoadingQueue.addOperation {
            let allContacts = UserDAO.shared.contacts()
            DispatchQueue.main.async {
                self.allContacts = allContacts
                if self.isPresenting && self.keyword.isEmpty {
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    private func showContacts() {
        if allContacts.isEmpty {
            reloadContacts()
        } else {
            tableView.reloadData()
        }
    }
    
    private func prepareForReuse() {
        keywordTextField.text = nil
        users = []
        assets = []
        conversations = []
        tableView.reloadData()
        beforePresentingConstraints.forEach {
            $0.priority = .defaultHigh
        }
        afterPresentingConstraints.forEach {
            $0.priority = .defaultLow
        }
        keywordTextField.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        view.layoutIfNeeded()
        tableView.contentOffset.y = -tableView.contentInset.top
    }

}

extension SearchViewController: UITableViewDataSource {

    func numberOfSections(in tableView: UITableView) -> Int {
        guard !keyword.isEmpty else {
            return 1
        }
        return (assets.count > 0 ? 1 : 0) + (users.count > 0 ? 1 : 0) + (conversations.count > 0 ? 1 : 0)
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if keyword.isEmpty {
            return allContacts.count
        } else {
            if assets.count > 0 && section == 0 {
                return assets.count
            } else if users.count > 0 && (section == 0 || (assets.count > 0 && section == 1)) {
                return users.count
            } else {
                return conversations.count
            }
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if keyword.isEmpty {
            let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseId, for: indexPath) as! SearchResultContactCell
            cell.render(user: allContacts[indexPath.row])
            return cell
        } else {
            let section = indexPath.section
            if section == 0 && assets.count > 0 {
                let cell = tableView.dequeueReusableCell(withIdentifier: SearchResultAssetCell.cellIdentifier, for: indexPath) as! SearchResultAssetCell
                cell.accessoryType = .none
                cell.render(asset: assets[indexPath.row])
                return cell
            } else if users.count > 0 && (section == 0 || (assets.count > 0 && section == 1)) {
                let cell = tableView.dequeueReusableCell(withIdentifier: contactCellReuseId, for: indexPath) as! SearchResultContactCell
                cell.render(user: users[indexPath.row])
                return cell
            } else {
                let cell = tableView.dequeueReusableCell(withIdentifier: conversationCellReuseId, for: indexPath) as! ConversationCell
                cell.render(item: conversations[indexPath.row])
                return cell
            }
        }
    }
}

extension SearchViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if keyword.isEmpty {
            return headerHeight
        } else {
            return assets.count > 0 || users.count > 0 || conversations.count > 0 ? headerHeight : .leastNormalMagnitude
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let header = tableView.dequeueReusableHeaderFooterView(withIdentifier: headerReuseId) as! GeneralTableViewHeader
        if keyword.isEmpty {
            header.label.text = Localized.SECTION_TITLE_CONTACTS
        } else {
            if assets.count > 0 && section == 0 {
                header.label.text = Localized.SECTION_TITLE_ASSETS
            } else if users.count > 0 && (section == 0 || (assets.count > 0 && section == 1)) {
                header.label.text = Localized.SECTION_TITLE_CONTACTS
            } else {
                header.label.text = Localized.SECTION_TITLE_MESSAGES
            }
        }
        return header
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if keyword.isEmpty {
            navigationController?.pushViewController(ConversationViewController.instance(ownerUser: allContacts[indexPath.row]), animated: true)
        } else {
            let section = indexPath.section
            if assets.count > 0 && section == 0 {
                navigationController?.pushViewController(AssetViewController.instance(asset: assets[indexPath.row]), animated: true)
            } else if users.count > 0 && (section == 0 || (assets.count > 0 && section == 1)) {
                navigationController?.pushViewController(ConversationViewController.instance(ownerUser: users[indexPath.row]), animated: true)
            } else {
                let conversation = conversations[indexPath.row]
                let highlight = ConversationDataSource.Highlight(keyword: keyword, messageId: conversation.messageId)
                let vc = ConversationViewController.instance(conversation: conversation, highlight: highlight)
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
}
