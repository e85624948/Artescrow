# 🎨 Artescrow - Artist Commission Escrow Contract

> **Pay only when art is delivered** ✨

Artescrow is a smart contract built on Stacks that provides secure escrow services for art commissions. Clients can safely commission artwork from artists with funds held in escrow until the work is completed and approved.

## 🚀 Features

- 💰 **Secure Escrow**: Funds are locked in the contract until artwork delivery
- 🎯 **Commission Management**: Create, accept, and track art commissions
- ⏰ **Deadline Protection**: Automatic refunds for expired commissions
- 🛡️ **Dispute Resolution**: Built-in dispute handling system
- 📋 **Status Tracking**: Real-time commission status updates
- 🔍 **Transparency**: All commission details are publicly viewable

## 📋 Commission Statuses

- `0` - **Pending**: Commission created, waiting for artist acceptance
- `1` - **In Progress**: Artist accepted and working on the commission
- `2` - **Completed**: Artist submitted artwork, waiting for client approval
- `3` - **Disputed**: Either party raised a dispute
- `4` - **Cancelled**: Commission cancelled before acceptance
- `5` - **Refunded**: Funds returned to client

## 🛠️ Usage

### For Clients

#### 1. Create a Commission
```clarity
(contract-call? .Artescrow create-commission 
  'SP1ARTIST... ;; artist principal
  u1000000     ;; amount in microSTX
  u1000        ;; deadline (block height)
  "Portrait commission, realistic style") ;; description
```

#### 2. Approve and Release Payment
```clarity
(contract-call? .Artescrow approve-and-release-payment u1) ;; commission-id
```

#### 3. Cancel Commission (if not accepted)
```clarity
(contract-call? .Artescrow cancel-commission u1)
```

#### 4. Request Refund (after deadline)
```clarity
(contract-call? .Artescrow refund-expired-commission u1)
```

### For Artists

#### 1. Accept Commission
```clarity
(contract-call? .Artescrow accept-commission u1) ;; commission-id
```

#### 2. Submit Artwork
```clarity
(contract-call? .Artescrow submit-artwork 
  u1 ;; commission-id
  "https://ipfs.io/ipfs/QmArtwork...") ;; artwork URL
```

### For Both Parties

#### Dispute Commission
```clarity
(contract-call? .Artescrow dispute-commission u1)
```

## 🔍 Read-Only Functions

### Get Commission Details
```clarity
(contract-call? .Artescrow get-commission u1)
```

### Check Escrow Balance
```clarity
(contract-call? .Artescrow get-escrow-balance u1)
```

### Get User's Commissions
```clarity
(contract-call? .Artescrow get-user-commissions 'SP1USER...)
```

### Get Commission Status
```clarity
(contract-call? .Artescrow get-commission-status u1)
```

## 🏗️ Development Setup

### Prerequisites
- [Clarinet](https://github.com/hirosystems/clarinet) installed
- Stacks wallet for testing

### Installation
```bash
git clone <repository-url>
cd artescrow
clarinet check
```

### Testing
```bash
clarinet test
```

### Deployment
```bash
clarinet deploy --testnet
```

## 🔐 Security Features

- ✅ **Access Control**: Only authorized users can perform specific actions
- ✅ **Fund Safety**: Escrow funds are locked until proper release conditions
- ✅ **Deadline Enforcement**: Automatic protection against indefinite holds
- ✅ **Dispute Resolution**: Contract owner can resolve disputes fairly
- ✅ **Input Validation**: All inputs are validated before processing

## 📊 Error Codes

- `u100` - Not authorized
- `u101` - Commission not found
- `u102` - Invalid status for operation
- `u103` - Insufficient funds
- `u104` - Commission already exists
- `u105` - Invalid amount
- `u106` - Deadline has passed
- `u107` - Deadline has not passed

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request
