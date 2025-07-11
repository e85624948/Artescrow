(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_COMMISSION_NOT_FOUND (err u101))
(define-constant ERR_INVALID_STATUS (err u102))
(define-constant ERR_INSUFFICIENT_FUNDS (err u103))
(define-constant ERR_ALREADY_EXISTS (err u104))
(define-constant ERR_INVALID_AMOUNT (err u105))
(define-constant ERR_DEADLINE_PASSED (err u106))
(define-constant ERR_DEADLINE_NOT_PASSED (err u107))
(define-constant ERR_ALREADY_RATED (err u108))
(define-constant ERR_CANNOT_RATE_SELF (err u109))
(define-constant ERR_INVALID_RATING (err u110))
(define-constant ERR_COMMISSION_NOT_COMPLETE (err u111))
(define-constant ERR_RATING_NOT_FOUND (err u112))

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

(define-map user-reputation
  { user: principal }
  {
    total-rating: uint,
    rating-count: uint,
    total-commissions: uint,
    total-completed: uint,
    total-disputed: uint,
    join-date: uint
  }
)

(define-map commission-ratings
  { commission-id: uint, rater: principal }
  {
    rating: uint,
    comment: (optional (string-ascii 500)),
    rated-at: uint,
    rated-user: principal
  }
)

(define-map user-rating-details
  { user: principal }
  {
    five-star: uint,
    four-star: uint,
    three-star: uint,
    two-star: uint,
    one-star: uint
  }
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
    (initialize-user-reputation tx-sender)
    (initialize-user-reputation artist)
    (increment-user-commission-count tx-sender)
    (increment-user-commission-count artist)
    
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
    (increment-user-completed-count (get artist commission))
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
    (increment-user-disputed-count (get client commission))
    (increment-user-disputed-count (get artist commission))
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

(define-public (rate-user (commission-id uint) (rating uint) (comment (optional (string-ascii 500))))
  (let
    (
      (commission (unwrap! (map-get? commissions { commission-id: commission-id }) ERR_COMMISSION_NOT_FOUND))
      (rater tx-sender)
      (rated-user (if (is-eq rater (get client commission)) (get artist commission) (get client commission)))
    )
    (asserts! (and (>= rating u1) (<= rating u5)) ERR_INVALID_RATING)
    (asserts! (not (is-eq rater rated-user)) ERR_CANNOT_RATE_SELF)
    (asserts! (or (is-eq rater (get client commission)) (is-eq rater (get artist commission))) ERR_NOT_AUTHORIZED)
    (asserts! (is-eq (get status commission) STATUS_COMPLETED) ERR_COMMISSION_NOT_COMPLETE)
    (asserts! (is-none (map-get? commission-ratings { commission-id: commission-id, rater: rater })) ERR_ALREADY_RATED)
    
    (map-set commission-ratings
      { commission-id: commission-id, rater: rater }
      {
        rating: rating,
        comment: comment,
        rated-at: stacks-block-height,
        rated-user: rated-user
      }
    )
    
    (update-user-rating rated-user rating)
    (ok true)
  )
)

(define-public (get-user-rating (user principal))
  (let
    (
      (reputation (get-user-reputation user))
      (rating-count (get rating-count reputation))
    )
    (if (> rating-count u0)
      (ok (/ (get total-rating reputation) rating-count))
      (ok u0)
    )
  )
)

(define-public (get-user-rating-breakdown (user principal))
  (let
    (
      (details (default-to 
        { five-star: u0, four-star: u0, three-star: u0, two-star: u0, one-star: u0 }
        (map-get? user-rating-details { user: user })
      ))
    )
    (ok details)
  )
)

(define-public (get-commission-rating (commission-id uint) (rater principal))
  (match (map-get? commission-ratings { commission-id: commission-id, rater: rater })
    rating (ok rating)
    ERR_RATING_NOT_FOUND
  )
)

(define-public (get-user-reputation-stats (user principal))
  (let
    (
      (reputation (get-user-reputation user))
      (rating-count (get rating-count reputation))
      (average-rating (if (> rating-count u0) (/ (get total-rating reputation) rating-count) u0))
      (completion-rate (if (> (get total-commissions reputation) u0) 
        (/ (* (get total-completed reputation) u100) (get total-commissions reputation)) 
        u0))
      (dispute-rate (if (> (get total-commissions reputation) u0) 
        (/ (* (get total-disputed reputation) u100) (get total-commissions reputation)) 
        u0))
    )
    (ok {
      average-rating: average-rating,
      total-ratings: rating-count,
      total-commissions: (get total-commissions reputation),
      completion-rate: completion-rate,
      dispute-rate: dispute-rate,
      join-date: (get join-date reputation)
    })
  )
)

(define-public (is-user-trustworthy (user principal))
  (let
    (
      (reputation (get-user-reputation user))
      (rating-count (get rating-count reputation))
      (average-rating (if (> rating-count u0) (/ (get total-rating reputation) rating-count) u0))
      (completion-rate (if (> (get total-commissions reputation) u0) 
        (/ (* (get total-completed reputation) u100) (get total-commissions reputation)) 
        u0))
      (dispute-rate (if (> (get total-commissions reputation) u0) 
        (/ (* (get total-disputed reputation) u100) (get total-commissions reputation)) 
        u0))
    )
    (ok (and 
      (>= average-rating u4)
      (>= completion-rate u80)
      (<= dispute-rate u20)
      (>= rating-count u3)
    ))
  )
)

(define-private (update-user-rating (user principal) (rating uint))
  (let
    (
      (current-reputation (get-user-reputation user))
      (current-details (default-to 
        { five-star: u0, four-star: u0, three-star: u0, two-star: u0, one-star: u0 }
        (map-get? user-rating-details { user: user })
      ))
      (new-total-rating (+ (get total-rating current-reputation) rating))
      (new-rating-count (+ (get rating-count current-reputation) u1))
    )
    (map-set user-reputation
      { user: user }
      (merge current-reputation {
        total-rating: new-total-rating,
        rating-count: new-rating-count
      })
    )
    (map-set user-rating-details
      { user: user }
      (if (is-eq rating u5)
        (merge current-details { five-star: (+ (get five-star current-details) u1) })
        (if (is-eq rating u4)
          (merge current-details { four-star: (+ (get four-star current-details) u1) })
          (if (is-eq rating u3)
            (merge current-details { three-star: (+ (get three-star current-details) u1) })
            (if (is-eq rating u2)
              (merge current-details { two-star: (+ (get two-star current-details) u1) })
              (merge current-details { one-star: (+ (get one-star current-details) u1) })
            )
          )
        )
      )
    )
  )
)

(define-private (initialize-user-reputation (user principal))
  (if (is-none (map-get? user-reputation { user: user }))
    (map-set user-reputation
      { user: user }
      {
        total-rating: u0,
        rating-count: u0,
        total-commissions: u0,
        total-completed: u0,
        total-disputed: u0,
        join-date: stacks-block-height
      }
    )
    true
  )
)

(define-private (increment-user-commission-count (user principal))
  (let
    (
      (current-reputation (get-user-reputation user))
    )
    (map-set user-reputation
      { user: user }
      (merge current-reputation {
        total-commissions: (+ (get total-commissions current-reputation) u1)
      })
    )
  )
)

(define-private (increment-user-completed-count (user principal))
  (let
    (
      (current-reputation (get-user-reputation user))
    )
    (map-set user-reputation
      { user: user }
      (merge current-reputation {
        total-completed: (+ (get total-completed current-reputation) u1)
      })
    )
  )
)

(define-private (increment-user-disputed-count (user principal))
  (let
    (
      (current-reputation (get-user-reputation user))
    )
    (map-set user-reputation
      { user: user }
      (merge current-reputation {
        total-disputed: (+ (get total-disputed current-reputation) u1)
      })
    )
  )
)

(define-private (get-user-reputation (user principal))
  (default-to 
    { total-rating: u0, rating-count: u0, total-commissions: u0, total-completed: u0, total-disputed: u0, join-date: u0 }
    (map-get? user-reputation { user: user })
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