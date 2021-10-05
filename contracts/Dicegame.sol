pragma ton-solidity >= 0.35.0;
pragma AbiHeader expire;

import "../interfaces/DicegameInterfaces.sol";

// a contract to play the game of dice
contract Dicegame is IDicegame {

    // Error codes
    uint constant ERROR_NO_PUBKEY = 101;
    uint constant ERROR_SENDER_IS_NOT_OWNER = 102;

    // bet range properties
    uint128 public _minBet;
    uint16 public _maxBetDivider;

    // state variables
    address public _ownerAddress;
    uint64 _rewardAt;
    uint16 _rewardPercent;

    // check that contract's message is signed with the owner's private key
    modifier onlyOwner() {
        require(tvm.pubkey() != 0, ERROR_NO_PUBKEY);
        require(msg.pubkey() == tvm.pubkey(), ERROR_SENDER_IS_NOT_OWNER);
        tvm.accept();
        _;
    }

    // class constructor called on deploy
    constructor(address ownerAddress, uint128 minBet, uint16 maxBetDivider) public onlyOwner {
        // assign state variables
        _ownerAddress = ownerAddress;
        _minBet = minBet;
        _maxBetDivider = maxBetDivider;
        _rewardAt = now + 30 days;
        _rewardPercent = 10;
    }

    /// internal function that checks if the bet is valid
    function checkBet(uint128 bet) private view returns (bool) {
        uint128 balance = address(this).balance;
        if (bet > balance / _maxBetDivider) {
            msg.sender.transfer(0, false, 64);
            return false;
        }
        if (bet < _minBet) {
            msg.sender.transfer(0, false, 64);
            return false;
        }
        return true;
    }

    // play the game of dice
    function roll(bool betOnFirst) external override {
        // check if bet is valid
        if (!checkBet(msg.value)) {
            return;
        }

        // set random seed and roll the dice two times
        rnd.setSeed(now);
        rnd.shuffle();
        uint8 firstRoll = rnd.next(6) + 1;
        uint8 secondRoll = rnd.next(6) + 1;

        // check if player has won
        uint128 payout = 0;
        string comment = "";
        if (
            (firstRoll > secondRoll && betOnFirst) ||
            (firstRoll < secondRoll && !betOnFirst)
        ) {
            comment.append("🎉 WIN!\n");
            payout = msg.value * 2;
        } else {
            comment.append("😞 LOSS\n");
        }

        // add bet to comment
        if (betOnFirst) {
            comment.append("Bet: 1st\n");
        } else {
            comment.append("Bet: 2nd\n");
        }

        // add roll result to comment
        comment.append(format("Roll: {}|{}", firstRoll, secondRoll));

        // build response payload
        TvmBuilder builder;
        builder.storeUnsigned(0, 0x20); // 32-bit prefix that contains zeros
        builder.store(comment);

        // send the payout
        msg.sender.transfer({
            value: payout,
            bounce: false,
            flag: 1,
            body: builder.toCell()
        });

        // check if it's time to reward the owner
        if (_rewardAt <= now) {
            uint128 reward = uint128 (address(this).balance / 100 * _rewardPercent);
            _ownerAddress.transfer({value: reward, bounce: false});
            _rewardAt = now + 30 days;
        }
    }

    function setMinBet(uint128 minBet) public onlyOwner {
        _minBet = minBet;
    }

    function setMaxBetDivider(uint16 maxBetDivider) public onlyOwner {
        _maxBetDivider = maxBetDivider;
    }

    function setRewardPercent(uint16 rewardPercent) public onlyOwner {
        _rewardPercent = rewardPercent;
    }

    receive() external pure {}

    fallback() external pure {}
}
