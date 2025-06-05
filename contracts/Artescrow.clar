(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_COMMISSION_NOT_FOUND (err u101))
(define-constant ERR_INVALID_STATUS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_DEADLINE_PASSED (err u106))
(define-constant ERR_DEADLINE_NOT_PASSED (err u107))

(define-constant STATUS_PENDING u0)
(define-constant STATUS_IN_PROGRESS u1)
(define-constant STATUS_COMPLETED u2)
(define-constant STATUS_DISPUTED u3)
(define-constant STATUS_CANCELLED u4)
(define-constant STATUS_REFUNDED u5)

(define-data-var commission-counter uint u0)

(define-map commissions
  { commission-id: uint }
  {
    client: principal,
    artist: principal,
    amount: uint,
    deadline: uint,
    status: uint,
    description: (string-ascii 500),
    artwork-url: (optional (string-ascii 200)),
    created-at: uint,
    completed-at: (optional uint)
  }
)

(define-map user-commissions
  { user: principal }
  { commission-ids: (list 100 uint) }
)

(define-map escrow-balances
  { commission-id: uint }
  { amount: uint }
)

(define-public (create-commission (artist principal) (amount uint) (deadline uint) (description (string-ascii 500)))
  (let
    (
      (commission-id (+ (var-get commission-counter) u1))
      (current-block stacks-block-height)
    )
    (asserts! (> amount u0) ERR_INVALID_AMOUNT)
    (asserts! (> deadline current-block) ERR_DEADLINE_PASSED)
    (asserts! (not (is-eq tx-sender artist)) ERR_NOT_AUTHORIZED)
    
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    
    (map-set commissions
      { commission-id: commission-id }
      {
        client: tx-sender,
        artist: artist,
        amount: amount,
        deadline: deadline,
        status: STATUS_PENDING,
        description: description,
        artwork-url: none,
        created-at: current-block,
        completed-at: none
      }
    )
    
    (map-set escrow-balances
      { commission-id: commission-id }
      { amount: amount }
    )
    
    (update-user-commissions tx-sender commission-id)
    (update-user-commissions artist commission-id)
    
    (var-set commission-counter commission-id)
    (ok commission-id)
  )
)

(define-public (accept-commission (commission-id uint))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get artist commission)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_PENDING) ERR_INVALID_STATUS)
    (asserts! (<= stacks-block-height (get deadline commission)) ERR_DEADLINE_PASSED)
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { status: STATUS_IN_PROGRESS })
    )
    (ok true)
  )
)

(define-public (submit-artwork (commission-id uint) (artwork-url (string-ascii 200)))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get artist commission)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_IN_PROGRESS) ERR_INVALID_STATUS)
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { 
        status: STATUS_COMPLETED,
        artwork-url: (some artwork-url),
        completed-at: (some stacks-block-height)
      })
    )
    (ok true)
  )
)

(define-public (approve-and-release-payment (commission-id uint))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (escrow (unwrap! (map-get? escrow-balances { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get client commission)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_COMPLETED) ERR_INVALID_STATUS)
    (asserts! (> (get amount escrow) u0) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get artist commission))))
    
    (map-set escrow-balances
      { commission-id: commission-id }
      { amount: u0 }
    )
    (ok true)
  )
)

(define-public (dispute-commission (commission-id uint))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (or (is-eq tx-sender (get client commission)) (is-eq tx-sender (get artist commission))) ERR_NOT_AUTHORIZED)
    (asserts! (or (is-eq (get status commission) STATUS_IN_PROGRESS) (is-eq (get status commission) STATUS_COMPLETED)) ERR_INVALID_STATUS)
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { status: STATUS_DISPUTED })
    )
    (ok true)
  )
)

(define-public (cancel-commission (commission-id uint))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (escrow (unwrap! (map-get? escrow-balances { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get client commission)) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_PENDING) ERR_INVALID_STATUS)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get client commission))))
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { status: STATUS_CANCELLED })
    )
    
    (map-set escrow-balances
      { commission-id: commission-id }
      { amount: u0 }
    )
    (ok true)
  )
)

(define-public (refund-expired-commission (commission-id uint))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (escrow (unwrap! (map-get? escrow-balances { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
    )
    (asserts! (is-eq tx-sender (get client commission)) ERR_NOT_AUTHORIZED)
    (asserts! (> stacks-block-height (get deadline commission)) ERR_DEADLINE_NOT_PASSED)
    (asserts! (is-eq (get status commission) STATUS_PENDING) ERR_INVALID_STATUS)
    (asserts! (> (get amount escrow) u0) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender (get client commission))))
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { status: STATUS_REFUNDED })
    )
    
    (map-set escrow-balances
      { commission-id: commission-id }
      { amount: u0 }
    )
    (ok true)
  )
)

(define-public (resolve-dispute (commission-id uint) (refund-to-client bool))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (escrow (unwrap! (map-get? escrow-balances { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (recipient (if refund-to-client (get client commission) (get artist commission)))
    )
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_DISPUTED) ERR_INVALID_STATUS)
    (asserts! (> (get amount escrow) u0) ERR_INSUFFICIENT_FUNDS)
    
    (try! (as-contract (stx-transfer? (get amount escrow) tx-sender recipient)))
    
    (map-set commissions
      { commission-id: commission-id }
      (merge commission { status: (if refund-to-client STATUS_REFUNDED STATUS_COMPLETED) })
    )
    
    (map-set escrow-balances
      { commission-id: commission-id }
      { amount: u0 }
    )
    (ok true)
  )
)

(define-read-only (get-commission (commission-id uint))
  (map-get? commissions { commission-id: commission-id })
)

(define-read-only (get-escrow-balance (commission-id uint))
  (map-get? escrow-balances { commission-id: commission-id })
)

(define-read-only (get-user-commissions (user principal))
  (default-to { commission-ids: (list) } (map-get? user-commissions { user: user }))
)

(define-read-only (get-commission-count)
  (var-get commission-counter)
)

(define-read-only (get-commission-status (commission-id uint))
  (match (map-get? commissions { commission-id: commission-id })
    commission (ok (get status commission))
    ERR_COMMISSION_NOT_FOUND
  )
)

(define-private (update-user-commissions (user principal) (commission-id uint))
  (let
    (
      (current-commissions (get commission-ids (get-user-commissions user)))
    )
    (map-set user-commissions
      { user: user }
      { commission-ids: (unwrap-panic (as-max-len? (append current-commissions commission-id) u100)) }
    )
  )
)