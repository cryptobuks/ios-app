import Foundation
import WCDBSwift
import Bugsnag

class SendMessageService: MixinService {

    static let shared = SendMessageService()
    private let dispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.send.messages")
    private let saveDispatchQueue = DispatchQueue(label: "one.mixin.messenger.queue.send")

    func restoreJobs() {
        let messages = MessageDAO.shared.getPendingMessages()
        for message in messages {
            if message.category.hasSuffix("_IMAGE") {
                ConcurrentJobQueue.shared.addJob(job: AttachmentUploadJob(message: message))
            } else if message.category.hasSuffix("_DATA") {
                if message.userId == AccountAPI.shared.accountUserId {
                    FileJobQueue.shared.addJob(job: FileUploadJob(message: message))
                } else {
                    FileJobQueue.shared.addJob(job: FileDownloadJob(messageId: message.messageId, mediaMimeType: message.mediaMimeType))
                }
            } else if message.category.hasSuffix("_VIDEO") {
                if message.userId == AccountAPI.shared.accountUserId {
                    FileJobQueue.shared.addJob(job: VideoUploadJob(message: message))
                } else {
                    FileJobQueue.shared.addJob(job: VideoDownloadJob(messageId: message.messageId, mediaMimeType: message.mediaMimeType))
                }
            } else if message.category.hasSuffix("_AUDIO") {
                if message.userId == AccountAPI.shared.accountUserId {
                    FileJobQueue.shared.addJob(job: AudioUploadJob(message: message))
                } else {
                    FileJobQueue.shared.addJob(job: AudioDownloadJob(messageId: message.messageId, mediaMimeType: message.mediaMimeType))
                }
            }
        }

        processMessages()
    }

    func sendMessage(message: Message, ownerUser: UserItem?, isGroupMessage: Bool) {
        guard let account = AccountAPI.shared.account else {
            return
        }

        var msg = message
        msg.userId = account.user_id
        msg.status = MessageStatus.SENDING.rawValue

        if !isGroupMessage {
            if let user = ownerUser {
                if user.isBot {
                    switch msg.category {
                    case MessageCategory.SIGNAL_TEXT.rawValue:
                        msg.category = MessageCategory.PLAIN_TEXT.rawValue
                    case MessageCategory.SIGNAL_DATA.rawValue:
                        msg.category = MessageCategory.PLAIN_DATA.rawValue
                    case MessageCategory.SIGNAL_IMAGE.rawValue:
                        msg.category = MessageCategory.PLAIN_IMAGE.rawValue
                    case MessageCategory.SIGNAL_STICKER.rawValue:
                        msg.category = MessageCategory.PLAIN_STICKER.rawValue
                    case MessageCategory.SIGNAL_CONTACT.rawValue:
                        msg.category = MessageCategory.PLAIN_CONTACT.rawValue
                    case MessageCategory.SIGNAL_VIDEO.rawValue:
                        msg.category = MessageCategory.PLAIN_VIDEO.rawValue
                    case MessageCategory.SIGNAL_AUDIO.rawValue:
                        msg.category = MessageCategory.PLAIN_AUDIO.rawValue
                    default:
                        break
                    }
                }
            } else {
                UIApplication.trackError("SendMessageService", action: "sendMessage owner is nil")
            }
        }

        if msg.conversationId.isEmpty || !ConversationDAO.shared.isExist(conversationId: msg.conversationId) {
            guard let user = ownerUser else {
                UIApplication.trackError("SendMessageService", action: "sendMessage ownerUser is empty")
                return
            }
            let conversationId = ConversationDAO.shared.makeConversationId(userId: account.user_id, ownerUserId: user.userId)
            msg.conversationId = conversationId

            let createdAt = Date().toUTCString()
            let participants = [ParticipantResponse(userId: user.userId, role: ParticipantRole.OWNER.rawValue, createdAt: createdAt), ParticipantResponse(userId: account.user_id, role: "", createdAt: createdAt)]
            let response = ConversationResponse(conversationId: conversationId, name: "", category: ConversationCategory.CONTACT.rawValue, iconUrl: user.avatarUrl, announcement: "", createdAt: Date().toUTCString(), participants: participants, codeUrl: "", creatorId: user.userId, muteUntil: "")
            ConversationDAO.shared.createConversation(conversation: response, targetStatus: .START)
        }
        if !message.category.hasPrefix("WEBRTC_") {
            MessageDAO.shared.insertMessage(message: msg, messageSource: "")
        }
        if msg.category.hasSuffix("_TEXT") || msg.category.hasSuffix("_STICKER") || message.category.hasSuffix("_CONTACT") {
            SendMessageService.shared.sendMessage(message: msg)
            SendMessageService.shared.sendSessionMessage(message: msg, data: message.content)
        } else if msg.category.hasSuffix("_IMAGE") {
            ConcurrentJobQueue.shared.addJob(job: AttachmentUploadJob(message: msg))
        } else if msg.category.hasSuffix("_DATA") {
            FileJobQueue.shared.addJob(job: FileUploadJob(message: msg))
        } else if msg.category.hasSuffix("_VIDEO") {
            FileJobQueue.shared.addJob(job: VideoUploadJob(message: msg))
        } else if msg.category.hasSuffix("_AUDIO") {
            FileJobQueue.shared.addJob(job: AudioUploadJob(message: msg))
        } else if message.category.hasPrefix("WEBRTC_"), let recipient = ownerUser {
            SendMessageService.shared.sendWebRTCMessage(message: message, recipientId: recipient.userId)
        }
    }

    func sendMessage(message: Message) {
        saveDispatchQueue.async {
            MixinDatabase.shared.insertOrReplace(objects: [Job(message: message)])
            SendMessageService.shared.processMessages()
        }
    }

    func sendSessionMessage(message: Message, representativeId: String? = nil, data: String?) {
        guard AccountUserDefault.shared.isDesktopLoggedIn else {
            return
        }
        guard message.category.hasSuffix("_TEXT") || message.category.hasSuffix("_STICKER") || message.category.hasSuffix("_CONTACT") || message.category.hasSuffix("_IMAGE") || message.category == MessageCategory.SYSTEM_CONVERSATION.rawValue else {
            return
        }
        let content = message.category == MessageCategory.PLAIN_TEXT.rawValue ? data?.base64Encoded() : data
        saveDispatchQueue.async {
            MixinDatabase.shared.insertOrReplace(objects: [Job(message: message, isSessionMessage: true, representativeId: representativeId, data: content)])
            SendMessageService.shared.processMessages()
        }
    }

    func sendSessionMessage(action: JobAction, messageId: String, status: String) {
        saveDispatchQueue.async {
            let job = Job(action: action, messageId: messageId, status: status, isSessionMessage: true)
            MixinDatabase.shared.insertOrReplace(objects: [job])
            SendMessageService.shared.processMessages()
        }
    }

    func sendWebRTCMessage(message: Message, recipientId: String) {
        saveDispatchQueue.async {
            MixinDatabase.shared.insertOrReplace(objects: [Job(webRTCMessage: message, recipientId: recipientId)])
            SendMessageService.shared.processMessages()
        }
    }

    func sendMessage(conversationId: String, userId: String, action: JobAction) {
        saveDispatchQueue.async {
            let job = Job(jobId: UUID().uuidString.lowercased(), action: action, userId: userId, conversationId: conversationId)
            MixinDatabase.shared.insertOrReplace(objects: [job])
            SendMessageService.shared.processMessages()
        }
    }

    func sendMessage(conversationId: String, userId: String, blazeMessage: BlazeMessage, action: JobAction) {
        saveDispatchQueue.async {
            let job = Job(jobId: blazeMessage.id, action: action, userId: userId, conversationId: conversationId, blazeMessage: blazeMessage)
            MixinDatabase.shared.insertOrReplace(objects: [job])
            SendMessageService.shared.processMessages()
        }
    }

    func resendMessages(conversationId: String, userId: String, messageIds: [String]) {
        var jobs = [Job]()
        var resendMessages = [ResendMessage]()
        for messageId in messageIds {
            guard !ResendMessageDAO.shared.isExist(messageId: messageId, userId: userId) else {
                continue
            }

            if MessageDAO.shared.isExist(messageId: messageId) {
                let param = BlazeMessageParam(conversationId: conversationId, recipientId: userId, status: MessageStatus.SENT.rawValue, messageId: messageId)
                let blazeMessage = BlazeMessage(params: param, action: BlazeMessageAction.createMessage.rawValue)
                jobs.append(Job(jobId: blazeMessage.id, action: .RESEND_MESSAGE, userId: userId, conversationId: conversationId, resendMessageId: UUID().uuidString.lowercased(), blazeMessage: blazeMessage))
                resendMessages.append(ResendMessage(messageId: messageId, userId: userId, status: 1))
            } else {
                resendMessages.append(ResendMessage(messageId: messageId, userId: userId, status: 0))
            }
        }

        saveDispatchQueue.async {
            MixinDatabase.shared.transaction(callback: { (database) in
                try database.insertOrReplace(objects: jobs, intoTable: Job.tableName)
                try database.insertOrReplace(objects: resendMessages, intoTable: ResendMessage.tableName)
            })
            SendMessageService.shared.processMessages()
        }
    }

    func sendReadMessages(conversationId: String) {
        saveDispatchQueue.async {
            let messageIds = MixinDatabase.shared.getStringValues(column: Message.Properties.messageId.asColumnResult(), tableName: Message.tableName, condition: Message.Properties.conversationId == conversationId && Message.Properties.status == MessageStatus.DELIVERED.rawValue, orderBy: [Message.Properties.createdAt.asOrder(by: .ascending)], inTransaction: false)
            guard messageIds.count > 0, let lastMessageId = messageIds.last, let lastCreatedAt = MixinDatabase.shared.scalar(on: Message.Properties.createdAt.asColumnResult(), fromTable: Message.tableName, condition: Message.Properties.messageId == lastMessageId)?.stringValue else {
                return
            }

            let jobs = messageIds.map { (messageId) -> Job in
                let blazeMessage = BlazeMessage(ackBlazeMessage: messageId, status: MessageStatus.READ.rawValue)
                return Job(jobId: blazeMessage.id, action: .SEND_ACK_MESSAGE, blazeMessage: blazeMessage)
            }
            let sessionJobs = messageIds.map { (messageId) -> Job in
                return Job(action: .SEND_SESSION_MESSAGE, messageId: messageId, status: MessageStatus.READ.rawValue, isSessionMessage: true)
            }

            MixinDatabase.shared.transaction { (database) in
                try database.insert(objects: jobs, intoTable: Job.tableName)
                try database.insert(objects: sessionJobs, intoTable: Job.tableName)
                try database.update(table: Message.tableName, on: [Message.Properties.status], with: [MessageStatus.READ.rawValue], where: Message.Properties.conversationId == conversationId && Message.Properties.status == MessageStatus.DELIVERED.rawValue && Message.Properties.createdAt <= lastCreatedAt && Message.Properties.userId != AccountAPI.shared.accountUserId)
                NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange)
            }
            SendMessageService.shared.processMessages()
        }
    }

    func sendReadMessage(messageId: String) {
        saveDispatchQueue.async {
            let blazeMessage = BlazeMessage(ackBlazeMessage: messageId, status: MessageStatus.READ.rawValue)
            let job = Job(jobId: blazeMessage.id, action: .SEND_ACK_MESSAGE, blazeMessage: blazeMessage)
            let sessionJob = Job(action: .SEND_SESSION_MESSAGE, messageId: messageId, status: MessageStatus.READ.rawValue, isSessionMessage: true)

            MixinDatabase.shared.transaction(callback: { (database) in
                let updateStatment = try database.prepareUpdate(table: Message.tableName, on: Message.Properties.status).where(Message.Properties.messageId == messageId && Message.Properties.status == MessageStatus.DELIVERED.rawValue)
                try updateStatment.execute(with: [MessageStatus.READ.rawValue])
                guard updateStatment.changes ?? 0 > 0 else {
                    return
                }
                try database.insert(objects: [job, sessionJob], intoTable: Job.tableName)
                NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange)
            })
            SendMessageService.shared.processMessages()
        }
    }

    func sendAckMessage(messageId: String, status: MessageStatus) {
        saveDispatchQueue.async {
            let blazeMessage = BlazeMessage(ackBlazeMessage: messageId, status: status.rawValue)
            let action: JobAction = status == .DELIVERED ? .SEND_DELIVERED_ACK_MESSAGE : .SEND_ACK_MESSAGE
            let job = Job(jobId: blazeMessage.id, action: action, blazeMessage: blazeMessage)
            MixinDatabase.shared.insertOrReplace(objects: [job])
            SendMessageService.shared.processMessages()
        }
    }

    func processMessages() {
        guard !processing else {
            return
        }
        processing = true

        dispatchQueue.async {
            defer {
                SendMessageService.shared.processing = false
            }
            repeat {
                guard let job = AccountUserDefault.shared.isDesktopLoggedIn ? JobDAO.shared.nextJob() : JobDAO.shared.nextNotSessionJob() else {
                    return
                }

                if job.action == JobAction.SEND_ACK_MESSAGE.rawValue || job.action == JobAction.SEND_DELIVERED_ACK_MESSAGE.rawValue {
                    let jobs = JobDAO.shared.nextBatchAckJobs(limit: 100)
                    let messages: [TransferMessage] = jobs.compactMap {
                        guard let params = $0.toBlazeMessage().params, let messageId = params.messageId, let status = params.status else {
                            return nil
                        }
                        return TransferMessage(messageId: messageId, status: status)
                    }

                    guard messages.count > 0 else {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                        return
                    }

                    let blazeMessage = BlazeMessage(params: BlazeMessageParam(messages: messages), action: BlazeMessageAction.acknowledgeMessageReceipts.rawValue)
                    if SendMessageService.shared.deliverMessages(blazeMessage: blazeMessage) {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                    }
                } else if job.action == JobAction.SEND_SESSION_MESSAGE.rawValue {
                    guard let sessionId = AccountUserDefault.shared.extensionSession else {
                        return
                    }

                    let jobs = JobDAO.shared.nextBatchJobs(action: .SEND_SESSION_MESSAGE, limit: 100)
                    let messages: [BlazeAckMessage] = jobs.compactMap {
                        guard let messageId = $0.messageId, let status = $0.status else {
                            return nil
                        }
                        return BlazeAckMessage(messageId: messageId, status: status)
                    }

                    guard messages.count > 0 else {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                        return
                    }

                    let transferPlainData = TransferPlainAckData(action: PlainDataAction.ACKNOWLEDGE_MESSAGE_RECEIPTS.rawValue, messages: messages)
                    let encoded = (try? JSONEncoder().encode(transferPlainData).base64EncodedString()) ?? ""
                    let accountId = AccountAPI.shared.accountUserId
                    let params = BlazeMessageParam(conversationId: accountId, recipientId: accountId, category: MessageCategory.PLAIN_JSON.rawValue, data: encoded, status: MessageStatus.SENDING.rawValue, messageId: UUID().uuidString.lowercased(), sessionId: sessionId, primitiveId: accountId)
                    let blazeMessage = BlazeMessage(params: params, action: BlazeMessageAction.createSessionMessage.rawValue)
                    if SendMessageService.shared.deliverMessages(blazeMessage: blazeMessage) {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                    }
                } else if job.action == JobAction.SEND_SESSION_ACK_MESSAGE.rawValue {
                    let jobs = JobDAO.shared.nextBatchJobs(action: .SEND_SESSION_ACK_MESSAGE, limit: 100)
                    let messages: [TransferMessage] = jobs.compactMap {
                        guard let messageId = $0.messageId, let status = $0.status else {
                            return nil
                        }
                        return TransferMessage(messageId: messageId, status: status)
                    }

                    guard messages.count > 0 else {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                        return
                    }

                    let blazeMessage = BlazeMessage(params: BlazeMessageParam(messages: messages), action: BlazeMessageAction.acknowledgeSessionMessageReceipts.rawValue)
                    if SendMessageService.shared.deliverMessages(blazeMessage: blazeMessage) {
                        JobDAO.shared.removeJobs(jobIds: jobs.map{ $0.jobId })
                    }
                } else {
                    guard SendMessageService.shared.handlerJob(job: job) else {
                        return
                    }

                    JobDAO.shared.removeJob(jobId: job.jobId)
                }
            } while true
        }
    }

    private func deliverMessages(blazeMessage: BlazeMessage) -> Bool {
        repeat {
            guard AccountAPI.shared.didLogin else {
                return false
            }

            do {
                try deliver(blazeMessage: blazeMessage)
                return true
            } catch {
                checkNetworkAndWebSocket()
                Bugsnag.notifyError(error)
            }
        } while true
    }

    private func handlerJob(job: Job) -> Bool {
        var job = job
        repeat {
            guard AccountAPI.shared.didLogin else {
                return false
            }
            let runCount = job.runCount + 1
            job.runCount = runCount
            JobDAO.shared.updateJobRunCount(jobId: job.jobId, runCount: runCount)

            do {
                switch job.action {
                case JobAction.SEND_MESSAGE.rawValue:
                    try ReceiveMessageService.shared.messageDispatchQueue.sync {
                        let blazeMessage = job.toBlazeMessage()
                        if blazeMessage.action == BlazeMessageAction.createCall.rawValue {
                            try SendMessageService.shared.sendCallMessage(blazeMessage: blazeMessage)
                        } else {
                            if job.isSessionMessage {
                                try SendMessageService.shared.sendSessionMessage(blazeMessage: blazeMessage)
                            } else {
                                try SendMessageService.shared.sendMessage(blazeMessage: blazeMessage, jobOrderId: job.orderId)
                            }
                        }
                    }
                case JobAction.RESEND_MESSAGE.rawValue:
                    try ReceiveMessageService.shared.messageDispatchQueue.sync {
                        try SendMessageService.shared.resendMessage(job: job)
                    }
                case JobAction.SEND_ACK_MESSAGE.rawValue, JobAction.SEND_DELIVERED_ACK_MESSAGE.rawValue:
                    try deliver(blazeMessage: job.toBlazeMessage())
                case JobAction.SEND_KEY.rawValue:
                    _ = try ReceiveMessageService.shared.messageDispatchQueue.sync { () -> Bool in
                        return try sendSenderKey(conversationId: job.conversationId!, recipientId: job.userId!)
                    }
                case JobAction.RESEND_KEY.rawValue:
                    _ = try ReceiveMessageService.shared.messageDispatchQueue.sync { () -> Bool in
                        return try resendSenderKey(conversationId: job.conversationId!, recipientId: job.userId!)
                    }
                case JobAction.REQUEST_RESEND_KEY.rawValue:
                    ReceiveMessageService.shared.messageDispatchQueue.sync {
                        let blazeMessage = job.toBlazeMessage()
                        deliverNoThrow(blazeMessage: blazeMessage)
                        FileManager.default.writeLog(conversationId: job.conversationId!, log: "[SendMessageService][REQUEST_RESEND_KEY]...messageId:\(blazeMessage.params?.messageId ?? "")")
                    }
                case JobAction.REQUEST_RESEND_MESSAGES.rawValue:
                    deliverNoThrow(blazeMessage: job.toBlazeMessage())
                case JobAction.SEND_NO_KEY.rawValue:
                    deliverNoThrow(blazeMessage: job.toBlazeMessage())
                default:
                    break
                }

                if let conversationId = job.conversationId, let userId = job.userId {
                    FileManager.default.writeLog(conversationId: conversationId, log: "[SendMessageService][\(job.action)]...ended...userId:\(userId)...runCount:\(job.runCount)...orderId:\(job.orderId ?? 0)...priority:\(job.priority)")
                }

                return true
            } catch {
                checkNetworkAndWebSocket()
                Bugsnag.notifyError(error)
            }
        } while true
    }
}

extension SendMessageService {


    private func resendMessage(job: Job) throws {
        var blazeMessage = job.toBlazeMessage()
        guard let messageId = blazeMessage.params?.messageId, let resendMessageId = job.resendMessageId, let recipientId = job.userId else {
            return
        }
        guard let message = MessageDAO.shared.getMessage(messageId: messageId), try checkSignalSession(recipientId: recipientId) else {
            return
        }

        blazeMessage.params?.category = message.category
        blazeMessage.params?.messageId = resendMessageId
        blazeMessage.params?.quoteMessageId = message.quoteMessageId
        blazeMessage.params?.data = try SignalProtocol.shared.encryptSessionMessageData(recipientId: recipientId, content: message.content ?? "", resendMessageId: messageId)
        try deliverMessage(blazeMessage: blazeMessage)

        FileManager.default.writeLog(conversationId: message.conversationId, log: "[SendMessageService][ResendMessage]...messageId:\(messageId)...resendMessageId:\(resendMessageId)...resendUserId:\(recipientId)")
    }

    private func sendSessionMessage(blazeMessage: BlazeMessage) throws {
        guard let messageId = blazeMessage.params?.messageId, let category = blazeMessage.params?.category, let sessionId = AccountUserDefault.shared.extensionSession else {
            return
        }

        var blazeMessage = blazeMessage
        blazeMessage.action = BlazeMessageAction.createSessionMessage.rawValue
        blazeMessage.params?.messageId = UUID().uuidString.lowercased()
        blazeMessage.params?.recipientId = AccountAPI.shared.accountUserId
        blazeMessage.params?.sessionId = sessionId
        blazeMessage.params?.primitiveMessageId = messageId
        if category.hasPrefix("SYSTEM_") {
            blazeMessage.params?.primitiveId = User.systemUser
        } else if category.hasPrefix("PLAIN_") {
            guard let message = MessageDAO.shared.getMessage(messageId: messageId) else {
                return
            }
            if let representativeId = blazeMessage.params?.representativeId, !representativeId.isEmpty {
                blazeMessage.params?.primitiveId = representativeId
                blazeMessage.params?.representativeId = message.userId
            } else {
                blazeMessage.params?.primitiveId = message.userId
            }
        } else if category.hasPrefix("SIGNAL_") {
            guard let message = MessageDAO.shared.getMessage(messageId: messageId) else {
                return
            }
            blazeMessage.params?.primitiveId = message.userId
            _ = try checkSignalSession(recipientId: AccountAPI.shared.accountUserId, sessionId: sessionId)

            let content = blazeMessage.params?.data ?? ""
            blazeMessage.params?.data =  try SignalProtocol.shared.encryptTransferSessionMessageData(recipientId: AccountAPI.shared.accountUserId, content: content, sessionId: sessionId)
        }
        try deliverMessage(blazeMessage: blazeMessage)
    }

    private func sendMessage(blazeMessage: BlazeMessage, jobOrderId: Int?) throws {
        var blazeMessage = blazeMessage
        guard let messageId = blazeMessage.params?.messageId, let message = MessageDAO.shared.getMessage(messageId: messageId) else {
            return
        }
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: message.conversationId) else {
            return
        }

        blazeMessage.params?.category = message.category
        blazeMessage.params?.quoteMessageId = message.quoteMessageId

        if message.category.hasPrefix("PLAIN_") {
            try requestCreateConversation(conversation: conversation)
            if message.category == MessageCategory.PLAIN_TEXT.rawValue {
                blazeMessage.params?.data = message.content?.base64Encoded()
            } else {
                blazeMessage.params?.data = message.content
            }
            try deliverMessage(blazeMessage: blazeMessage)
        } else {
            let isExistSenderKey = SignalProtocol.shared.isExistSenderKey(groupId: message.conversationId, senderId: message.userId)
            if (isExistSenderKey) {
                try checkSentSenderKey(conversationId: message.conversationId)
            } else {
                if (conversation.isGroup()) {
                    switch ConversationAPI.shared.getConversation(conversationId: message.conversationId) {
                    case let .success(response):
                        ConversationDAO.shared.updateConversation(conversation: response)
                        try sendGroupSenderKey(conversationId: conversation.conversationId)
                    case let .failure(error):
                        if error.code == 404 && conversation.status == ConversationStatus.START.rawValue {
                            try requestCreateConversation(conversation: conversation)
                            try sendGroupSenderKey(conversationId: conversation.conversationId)
                            break
                        } else if error.code == 404 || error.code == 403 {
                            ParticipantDAO.shared.removeParticipant(conversationId: message.conversationId)
                            return
                        }
                        throw error
                    }
                } else {
                    try requestCreateConversation(conversation: conversation)
                    try sendSenderKey(conversationId: conversation.conversationId, recipientId: conversation.ownerId)
                }
            }

            blazeMessage.params?.data = try SignalProtocol.shared.encryptGroupMessageData(conversationId: message.conversationId, senderId: message.userId, content: message.content ?? "")
            try deliverMessage(blazeMessage: blazeMessage)

            FileManager.default.writeLog(conversationId: message.conversationId, log: "[SendMessageService][SendMessage][\(message.category)]...isExistSenderKey:\(isExistSenderKey)...messageId:\(messageId)...messageStatus:\(message.status)...orderId:\(jobOrderId ?? 0)")
        }
    }
    
    private func sendCallMessage(blazeMessage: BlazeMessage) throws {
        let onlySendWhenThereIsAnActiveCall = blazeMessage.params?.category == MessageCategory.WEBRTC_AUDIO_OFFER.rawValue
            || blazeMessage.params?.category == MessageCategory.WEBRTC_AUDIO_ANSWER.rawValue
            || blazeMessage.params?.category == MessageCategory.WEBRTC_ICE_CANDIDATE.rawValue
        guard CallManager.shared.call != nil || !onlySendWhenThereIsAnActiveCall else {
            return
        }
        guard let conversationId = blazeMessage.params?.conversationId else {
            return
        }
        guard let conversation = ConversationDAO.shared.getConversation(conversationId: conversationId) else {
            return
        }
        try requestCreateConversation(conversation: conversation)
        try deliverMessage(blazeMessage: blazeMessage)
    }

    private func deliverMessage(blazeMessage: BlazeMessage) throws {
        do {
            try deliver(blazeMessage: blazeMessage)
        } catch {
            if let err = error as? APIError, err.code == 403 {
                return
            }
            throw error
        }
    }

    private func requestCreateConversation(conversation: ConversationItem) throws {
        guard conversation.status == ConversationStatus.START.rawValue else {
            return
        }

        let participants = ParticipantDAO.shared.participantRequests(conversationId: conversation.conversationId, currentAccountId: currentAccountId)
        let request = ConversationRequest(conversationId: conversation.conversationId, name: nil, category: conversation.category, participants: participants, duration: nil, announcement: nil)
        switch ConversationAPI.shared.createConversation(conversation: request) {
        case let .success(response):
            ConversationDAO.shared.createConversation(conversation: response, targetStatus: .SUCCESS)
        case let .failure(error):
            if error.code == 10002 {
                MessageDAO.shared.clearChat(conversationId: conversation.conversationId, autoNotification: false)
            }
            throw error
        }
    }

    private func checkSentSenderKey(conversationId: String) throws {
        let participants = ParticipantDAO.shared.getNotSentKeyParticipants(conversationId: conversationId, accountId: currentAccountId)
        if participants.count == 1 {
            _ = try sendSenderKey(conversationId: conversationId, recipientId: participants[0].userId)
        } else if participants.count > 1 {
            try sendBatchSenderKey(conversationId: conversationId, participants: participants, from: "checkSentSenderKey")
        }
    }

}
