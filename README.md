# Game of Dice and Dicegame Debot

This repository contains Dicegame smart contract source code and Dicegame Debot smart contract source code.

## What is Game of Dice

The Game of Dice is very simple.

There are two dices. Player can choose a winning dice and make a bet.
If player wins the contract transfers back twice as much as was the bet.

Dicegame contract provides the logic and stores the bank.

Dicegame Debot provides a chat-based interface to play Dicegame contract.

To run Dicegame Debot in Surf open following link

> [0:9d8960d87978f503b05324078a1655cdd7afd152a2fd07dfb155907d095bc417](https://uri.ton.surf/debot/0:9d8960d87978f503b05324078a1655cdd7afd152a2fd07dfb155907d095bc417)

## How to play the Game of Dice

- click "Start new game" menu item
- attach you multisignature wallet
- click "ROLL!"
- check transaction from Dicegame contract

### How to change bet amount

Click "Bet x 2" button to double current bet. To set bet manually click "Set bet manually".

### How to change winning dice

Click "Switch winning dice" button.

### How to see game summary

In Game menu there is a game summary showing game address, min bet, max bet, max payout and total payouts amount.

### How to change the Dicegame to play with

Click "Back to main menu" to get back to main menu.

Click "Select dicegame contract" to get list of available contracts.

Enter Dicegame number you wish to play with.

### How to play in CLI

Dicegame Debot can be run using [`tondev`](https://github.com/tonlabs/tondev):

#### DevNet

```
tonos-cli --url net.ton.dev debot fetch 0:9d8960d87978f503b05324078a1655cdd7afd152a2fd07dfb155907d095bc417
```

#### Free TON

```
tonos-cli --url main.ton.dev debot fetch 0:9d8960d87978f503b05324078a1655cdd7afd152a2fd07dfb155907d095bc417
```
