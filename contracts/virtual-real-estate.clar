;; Virtual Real Estate Platform

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-already-exists (err u103))
(define-constant err-invalid-value (err u104))

;; Define NFT token
(define-non-fungible-token virtual-property uint)

;; Data Maps
(define-map properties
  { property-id: uint }
  {
    owner: principal,
    price: uint,
    zone: (string-ascii 20),
    last-tax-payment: uint,
    improvements: uint
  }
)

(define-map zones
  { zone: (string-ascii 20) }
  {
    max-improvements: uint,
    tax-rate: uint
  }
)

;; Variables
(define-data-var last-property-id uint u0)
(define-data-var tax-period uint u52560) ;; Approximately 1 year in blocks (10 minute block time)

;; Private Functions
(define-private (is-owner)
  (is-eq tx-sender contract-owner)
)

;; Public Functions
(define-public (create-property (zone (string-ascii 20)))
  (let
    (
      (new-property-id (+ (var-get last-property-id) u1))
    )
    (asserts! (is-some (map-get? zones { zone: zone })) err-not-found)
    (try! (nft-mint? virtual-property new-property-id tx-sender))
    (map-set properties { property-id: new-property-id }
      {
        owner: tx-sender,
        price: u0,
        zone: zone,
        last-tax-payment: block-height,
        improvements: u0
      }
    )
    (var-set last-property-id new-property-id)
    (ok new-property-id)
  )
)

(define-public (set-price (property-id uint) (new-price uint))
  (let
    (
      (property (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
    )
    (asserts! (is-eq (get owner property) tx-sender) err-unauthorized)
    (map-set properties { property-id: property-id }
      (merge property { price: new-price })
    )
    (ok true)
  )
)

(define-public (buy-property (property-id uint))
  (let
    (
      (property (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
    )
    (asserts! (> (get price property) u0) err-invalid-value)
    (try! (stx-transfer? (get price property) tx-sender (get owner property)))
    (try! (nft-transfer? virtual-property property-id (get owner property) tx-sender))
    (map-set properties { property-id: property-id }
      (merge property
        {
          owner: tx-sender,
          price: u0
        }
      )
    )
    (ok true)
  )
)

(define-public (improve-property (property-id uint) (improvement-value uint))
  (let
    (
      (property (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
      (zone-info (unwrap! (map-get? zones { zone: (get zone property) }) err-not-found))
    )
    (asserts! (is-eq (get owner property) tx-sender) err-unauthorized)
    (asserts! (<= (+ (get improvements property) improvement-value) (get max-improvements zone-info)) err-invalid-value)
    (map-set properties { property-id: property-id }
      (merge property
        { improvements: (+ (get improvements property) improvement-value) }
      )
    )
    (ok true)
  )
)

(define-public (pay-property-tax (property-id uint))
  (let
    (
      (property (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
      (zone-info (unwrap! (map-get? zones { zone: (get zone property) }) err-not-found))
      (tax-due (calculate-tax property zone-info))
    )
    (asserts! (is-eq (get owner property) tx-sender) err-unauthorized)
    (try! (stx-transfer? tax-due tx-sender (as-contract tx-sender)))
    (map-set properties { property-id: property-id }
      (merge property { last-tax-payment: block-height })
    )
    (ok true)
  )
)

(define-private (calculate-tax (property { owner: principal, price: uint, zone: (string-ascii 20), last-tax-payment: uint, improvements: uint }) (zone-info { max-improvements: uint, tax-rate: uint }))
  (let
    (
      (periods-elapsed (/ (- block-height (get last-tax-payment property)) (var-get tax-period)))
      (property-value (+ (get price property) (* (get improvements property) u1000)))
    )
    (* property-value (get tax-rate zone-info) periods-elapsed)
  )
)

;; Admin Functions
(define-public (set-zone (zone (string-ascii 20)) (max-improvements uint) (tax-rate uint))
  (begin
    (asserts! (is-owner) err-owner-only)
    (map-set zones { zone: zone }
      {
        max-improvements: max-improvements,
        tax-rate: tax-rate
      }
    )
    (ok true)
  )
)

(define-public (set-tax-period (new-period uint))
  (begin
    (asserts! (is-owner) err-owner-only)
    (var-set tax-period new-period)
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-property (property-id uint))
  (map-get? properties { property-id: property-id })
)

(define-read-only (get-zone (zone (string-ascii 20)))
  (map-get? zones { zone: zone })
)

(define-read-only (get-tax-due (property-id uint))
  (let
    (
      (property (unwrap! (map-get? properties { property-id: property-id }) err-not-found))
      (zone-info (unwrap! (map-get? zones { zone: (get zone property) }) err-not-found))
    )
    (ok (calculate-tax property zone-info))
  )
)
