;;; telega-info.el --- Users/Secrets/Groups stuff for telega

;; Copyright (C) 2018 by Zajcev Evgeny.

;; Author: Zajcev Evgeny <zevlg@yandex.ru>
;; Created: Fri Apr 20 00:24:21 2018
;; Keywords:

;; telega is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; telega is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with telega.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;;

;;; Code:
(require 'telega-core)
(require 'telega-server)

;; Info
(defmacro telega--info-update (tlobj)
  `(puthash (plist-get ,tlobj :id) ,tlobj
            (cdr (assq (telega--tl-type ,tlobj) telega--info))))

(defun telega--info (tlobj-type tlobj-id)
  (let* ((info-hash (cdr (assq tlobj-type telega--info)))
         (info (gethash tlobj-id info-hash)))
    (unless info
      (setq info (telega-server--call
                  (ecase tlobj-type
                    (user
                     `(:@type "getUser" :user_id ,tlobj-id))
                    (secretChat
                     `(:@type "getSecretChat" :secret_chat_id ,tlobj-id))
                    (basicGroup
                     `(:@type "getBasicGroup" :basic_group_id ,tlobj-id))
                    (supergroup
                     `(:@type "getSupergroup" :supergroup_id ,tlobj-id)))))
      (assert info nil "getting info for %S(id=%S) timeout" tlobj-type tlobj-id)
      (puthash tlobj-id info info-hash))
    info))

(defun telega--on-updateUser (event)
  (let ((user (plist-get event :user)))
    (telega--info-update user)
    (run-hook-with-args 'telega-user-update-hook user)))

(defun telega--on-updateBasicGroup (event)
  (telega--info-update (plist-get event :basic_group)))

(defun telega--on-updateSupergroup (event)
  (telega--info-update (plist-get event :supergroup)))

(defun telega--on-updateSecretChat (event)
  (telega--info-update (plist-get event :secret_chat)))

;; FullInfo
(defun telega--on-updateUserFullInfo (event)
  (let ((ufi (cdr (assq 'user telega--full-info))))
    (puthash (plist-get event :user_id)
             (plist-get event :user_full_info) ufi)))

(defun telega--on-updateBasicGroupFullInfo (event)
  (let ((ufi (cdr (assq 'basicGroup telega--full-info))))
    (puthash (plist-get event :basic_group_id)
             (plist-get event :basic_group_full_info) ufi)))

(defun telega--on-updateSupergroupFullInfo (event)
  (let ((ufi (cdr (assq 'supergroup telega--full-info))))
    (puthash (plist-get event :supergroup_id)
             (plist-get event :supergroup_full_info) ufi)))

(defun telega--full-info (tlobj)
  "Get FullInfo for the TLOBJ.
TLOBJ could be one of: user, basicgroup or supergroup."
  (let* ((tlobj-type (telega--tl-type tlobj))
         (tlobj-id (plist-get tlobj :id))
         (fi-hash (cdr (assq tlobj-type telega--full-info)))
         (full-info (gethash tlobj-id fi-hash)))
    (unless full-info
      (setq full-info
            (telega-server--call
             (ecase tlobj-type
               (user
                `(:@type "getUserFullInfo" :user_id ,tlobj-id))
               (basicGroup
                `(:@type "getBasicGroupFullInfo" :basic_group_id ,tlobj-id))
               (supergroup
                `(:@type "getSupergroupFullInfo" :supergroup_id ,tlobj-id)))))
      (assert full-info nil
              "getting full-info for type=%S timeout" tlobj-type)
      (puthash tlobj-id full-info fi-hash))
    full-info))


(defun telega-user--get (user-id)
  "Get user by USER-ID."
  (telega--info 'user user-id))

(defun telega-user--me ()
  "Return me as telegram user."
  (telega-server--call `(:@type "getMe")))

(defun telega-user--type (user)
  "Return USER type."
  (intern (downcase (substring (plist-get (plist-get user :type) :@type) 8))))

(defun telega-user--bot-p (user)
  "Return non-nil if USER is bot."
  (eq (telega-user--type user) 'bot))

(defun telega-user--title (user &optional with-username)
  "Return title for the USER."
  (if (eq (telega-user--type user) 'deleted)
      (format "DeletedUser-%d" (plist-get user :id))

    (let ((fn (plist-get user :first_name))
          (ln (plist-get user :last_name))
          (title ""))
      (when with-username
        (let ((un (plist-get user :username)))
          (unless (string-empty-p un)
            (setq title (concat "@" un)))))
      (unless (string-empty-p ln)
        (setq title (concat ln (if (string-empty-p title) "" " ") title)))
      (unless (string-empty-p fn)
        (setq title (concat fn (if (string-empty-p title) "" " ") title)))
      title)))

(defun telega-user--short-name (user)
  "Return short name for the USER."
  (let ((username (plist-get user :username)))
    (if (string-empty-p username)
        (concat (plist-get user :first_name)
                " "
                (plist-get user :last_name))
      (concat "@" username))))

(defun telega-user--seen (user)
  "Return last seen status for the USER."
  (substring (plist-get (plist-get user :status) :@type) 10))

(defun telega--on-updateUserStatus (event)
  "User status has been changed."
  (let ((user (telega-user--get (plist-get event :user_id))))
    (plist-put user :status (plist-get event :status))
    (run-hook-with-args 'telega-user-update-hook user)))

(defun telega-user--chats-in-common (with-user)
  "Return CHATS in common WITH-USER."
  (let* ((gic-cnt (plist-get (telega--full-info with-user) :group_in_common_count))
         (gic (when (> gic-cnt 0)
                (telega-server--call
                 `(:@type "getGroupsInCommon"
                          :user_id ,(plist-get with-user :id)
                          :offset_chat_id 0 :limit ,gic-cnt)))))
    (mapcar #'telega-chat--get (plist-get gic :chat_ids))))

(defun telega-supergroup--getMembers (supergroup &optional filter)
  "Get SUPERGRUOP members.
Default FILTER is \"supergroupMembersFilterRecent\"."
  (telega-server--call
   (list :@type "getSupergroupMembers"
         :supergroup_id (plist-get supergroup :id)
         :filter (list :@type (or filter "supergroupMembersFilterRecent"))
         :offset 0
         :limit 200)))

(defun telega-info--insert-user (user)
  "Insert USER info into current buffer."
  (let* ((full-info (telega--full-info user))
         (username (plist-get user :username))
         (phone_number (plist-get user :phone_number))
         (bio (plist-get full-info :bio))
         (share-text (plist-get full-info :share_text)))
    (unless (string-empty-p username)
      (insert (format "Username: @%s\n" username)))
    (unless (string-empty-p phone_number)
      (insert (format "phone: +%s\n" phone_number)))
    (insert (format "Seen: %s\n" (telega-user--seen user)))
    (unless (string-empty-p bio)
      (insert (telega-fmt-labeled-text "bio: " bio) "\n"))
    (unless (string-empty-p share-text)
      (insert (telega-fmt-labeled-text "Share text: " share-text) "\n")))

  (let ((chats-in-common (telega-user--chats-in-common user)))
    (when chats-in-common
      (insert (format "%d chats in common:\n" (length chats-in-common)))
      (dolist (chat chats-in-common)
        (insert "    ")
        (telega-button-insert 'telega-chat
          :value chat
          :format '("[" (telega-chat--title
                         :min 25 :max 25
                         :align left :align-char ?\s
                         :elide t :elide-trail 0)
                    "]"))
        (insert "\n"))))

    ;; TODO: view shared media as thumbnails
  )

(defun telega-info--insert-secretchat (secretchat)
  (insert "!TODO!\n")
  (insert (format "Info: %S\n\n" secretchat))
  )

(defun telega-info--insert-basicgroup (basicgroup)
  (let* ((full-info (telega--full-info basicgroup))
         (invite-link (plist-get full-info :invite_link))
         (members (plist-get full-info :members))
         (creator-id (plist-get full-info :creator_user_id))
         (creator (telega-user--get creator-id))
         (creator-member
          (cl-find creator-id members
                   :test (lambda (crt-id m)
                           (= crt-id (plist-get m :user_id)))))
         )
    (insert (format "Created: %s  %s\n"
                    (telega-user--title creator 'with-username)
                    (if creator-member
                        (telega-fmt-timestamp
                         (plist-get creator-member :joined_chat_date))
                      "")))
    (unless (string-empty-p invite-link)
      (insert "Invite link: ")
      (insert-text-button invite-link 'follow-link t)
      (insert "\n"))

    (insert (format "Members: %d users\n"
                    (plist-get basicgroup :member_count)))
    (mapc (lambda (mbr)
            (insert (format "  %s (%S)\n"
                            (telega-user--title
                             (telega-user--get (plist-get mbr :user_id))
                             'with-username)
                            (plist-get mbr :user_id))))
          members)
    ))

(defun telega-info--insert-supergroup (supergroup &optional chat)
  (let* ((full-info (telega--full-info supergroup))
         (invite-link (plist-get full-info :invite_link))
         (descr (plist-get full-info :description))
         (restr_reason (plist-get supergroup :restriction_reason))
         (pin_msg_id (plist-get full-info :pinned_message_id))
         (member-status (plist-get supergroup :status)))
    (insert "Status: " (substring (plist-get member-status :@type) 16) "\n")
    (insert (if (or (eq (telega--tl-type member-status)
                        'chatMemberStatusMember)
                    (and (memq (telega--tl-type member-status)
                               '(chatMemberStatusRestricted
                                 chatMemberStatusCreator))
                         (telega--tl-bool member-status :is_member)))
                "Joined at: "
              "Created at: ")
            (telega-fmt-timestamp (plist-get supergroup :date))
            "\n")

    (unless (string-empty-p invite-link)
      (insert "Invite link: ")
      (insert-text-button invite-link 'follow-link t)
      (insert "\n"))
    (unless (string-empty-p descr)
      (insert (telega-fmt-labeled-text "Desc: " descr) "\n"))
    (unless (string-empty-p restr_reason)
      (insert (telega-fmt-labeled-text "Restriction: " restr_reason) "\n"))

    (unless (zerop pin_msg_id)
      (insert "----(pinned message)----\n")
      (telega-button-insert 'telega-msg
        :format (lambda (msg)
                  (if (zerop (plist-get msg :sender_user_id))
                      (telega-msg-button--format-msg msg "")
                    (telega-msg-button--format-full msg)))
        :value (telega-chat--getPinnedMessage chat)
        :action 'ignore)
      (insert "------------------------\n"))

    (insert (format "Members: %d" (plist-get full-info :member_count)) "\n")
    (when (telega--tl-bool full-info :can_get_members)
      (mapc (lambda (member)
              (insert "  " (telega-fmt-eval 'telega-fmt-chat-member member) "\n"))
            (plist-get (telega-supergroup--getMembers supergroup) :members)))))

(defun telega-info--insert (tlobj chat)
  "Insert information about TLOBJ into current buffer."
  (ecase (telega--tl-type tlobj)
    (chatTypePrivate
     (telega-info--insert-user
      (telega--info 'user (plist-get tlobj :user_id))))
    (chatTypeSecret
     (telega-info--insert-secretchat
      (telega--info 'secretChat (plist-get tlobj :secret_chat_id))))
    (chatTypeBasicGroup
     (telega-info--insert-basicgroup
      (telega--info 'basicGroup (plist-get tlobj :basic_group_id))))
    (chatTypeSupergroup
     (telega-info--insert-supergroup
      (telega--info 'supergroup (plist-get tlobj :supergroup_id)) chat))))

(defun telega-describe-active-sessions ()
  "Describe active sessions."
  (interactive)
  (with-help-window "*Telega Active Sessions*"
    (set-buffer standard-output)
    (mapc (lambda (session)
            (let ((app_name (plist-get session :application_name))
                  (app_ver (plist-get session :application_version))
                  (api_id (plist-get session :api_id))
                  (official-p (telega--tl-bool session :is_official_application))
                  (current-p (telega--tl-bool session :is_current))
                  (device (plist-get session :device_model))
                  (platform (plist-get session :platform))
                  (sys_ver (plist-get session :system_version))
                  (ip (plist-get session :ip))
                  (country (plist-get session :country))
                  (login-ts (plist-get session :log_in_date))
                  (last-ts (plist-get session :last_active_date)))
              (insert (format "%s v%s " app_name app_ver)
                      (if official-p
                          "(official)"
                        (format "(ID:%s)" api_id))
                      (if current-p
                          " (current)"
                        "")
                      "\n")
              (insert (format "%s, %s %s\n" device platform sys_ver))
              (insert (format "%s %s\n" ip country))
              (insert (format "Login: %s, Last: %s\n"
                              (telega-fmt-timestamp login-ts)
                              (telega-fmt-timestamp last-ts)))
              (insert "\n")
              ))
          (plist-get (telega-server--call '(:@type "getActiveSessions"))
                     :sessions))))

(defun telega-describe-terms-of-service ()
  "Describe terms of service use."
  (interactive)
  (with-help-window "*Telega Terms Of Service*"
    (set-buffer standard-output)
    (insert (plist-get (telega-server--call `(:@type "getTermsOfService"))
                       :text))))

(provide 'telega-info)

;;; telega-info.el ends here
