pragma ton-solidity >=0.42.0;
pragma AbiHeader time;
pragma AbiHeader pubkey;
pragma AbiHeader expire;

import "../interfaces/Debot.sol";
import "../interfaces/DicegameInterfaces.sol";
import "../interfaces/Upgradable.sol";

import "../interfaces/debot/Menu.sol";
import "../interfaces/debot/AddressInput.sol";
import "../interfaces/debot/AmountInput.sol";
import "../interfaces/debot/Sdk.sol";
import "../interfaces/debot/SigningBoxInput.sol";
import "../interfaces/debot/Network.sol";
import "../interfaces/debot/Json.sol";
import "../interfaces/debot/Terminal.sol";

contract DicegameDebot is Debot, Upgradable
{
    // Error codes
    uint constant ERROR_NO_PUBKEY = 101;
    uint constant ERROR_SENDER_IS_NOT_OWNER = 102;

    // networks
    uint constant NETWORK_TESTNET = 1;
    uint constant NETWORK_MAINNET = 2;

    // dicegame parameters struct
    struct GameParams {
        address addr;
        uint128 minBet;
        uint16 maxBetDivider;
        uint128 balance;
        uint128 sumPayouts;
        uint128 maxPayout;
    }

    // list of dicegames and current dicegame index
    GameParams[] _games;
    uint32 _currentGameIndex = 0;

    // debot options
    bytes _icon;
    uint8 _network;

    // bet options
    address _multisigAddress;
    bool _isFirst = true;
    uint128 _betAmount;
    uint32 _keyHandle;

    modifier onlyOwner() {
        require(tvm.pubkey() != 0, ERROR_NO_PUBKEY);
        require(msg.pubkey() == tvm.pubkey(), ERROR_SENDER_IS_NOT_OWNER);
        tvm.accept();
        _;
    }

    constructor(uint8 network) public onlyOwner {
        _network = network;
    }

    function addDicegame(address addr, uint128 minBet, uint16 maxBetDivider) public onlyOwner {
        _games.push(GameParams(addr, minBet, maxBetDivider, 0, 0, 0));
    }

    function updateDicegame(address addr, uint128 minBet, uint16 maxBetDivider) public onlyOwner {
        uint32 i;
        for (i = 0; i < _games.length; i++) {
            if (_games[i].addr == addr) {
                _games[i].minBet = minBet;
                _games[i].maxBetDivider = maxBetDivider;
            }
        }
    }

    //========================================
    /// @notice Entry point function for DeBot.
    function start() public override {
        _start();
    }

    //========================================
    /// @notice Main menu
    function _start() public {
        loadGamesBalances();
        loadCurrentGameStats();

        Menu.select("Want to play the Game of Dice?", "", [
            MenuItem("Start new game", "", tvm.functionId(startGameMenu)),
            MenuItem("Select dicegame contract", "", tvm.functionId(selectDicegame)),
            MenuItem("Select wallet", "", tvm.functionId(selectWallet)),
            MenuItem("Exit", "", 0)
        ]);
    }

    //========================================
    /// @notice Game menu
    function startGameMenu() public {

        // check if user has wallet selected
        if (_multisigAddress == address(0)) {
            Terminal.print(0, "You don't have a wallet to play from.");
            selectWallet();
            return;
        }

        // load games balances and current game payout stats
        loadCurrentGameBalance();
        loadCurrentGameStats();

        // show game summary and bet summary
        showCurrentGameStats();
        showRollSummary();

        // game menu
        Menu.select("Start the game", "", [
            MenuItem("ROLL!", "", tvm.functionId(rollDice)),
            MenuItem("Switch winning dice", "", tvm.functionId(switchDice)),
            MenuItem("Bet x 2", "", tvm.functionId(doubleTheBet)),
            MenuItem("Set bet manually", "", tvm.functionId(setTheBet)),
            MenuItem("Back to main menu", "", tvm.functionId(_start))
        ]);
    }

    //========================================
    // game stats and roll summary
    function showCurrentGameStats() public {

        string stats = "Dicegame\n";
        stats.append(format("Address: {}\n", formatAddress(_games[_currentGameIndex].addr)));
        stats.append(format("Min/max bet: {}/{}\n", formatAmount(getMinBet(_currentGameIndex)), formatAmount(getMaxBet(_currentGameIndex))));

        if (_games[_currentGameIndex].maxPayout > 0) {
            stats.append(format("Max payout: {} TON\n", formatAmount(_games[_currentGameIndex].maxPayout)));
            stats.append(format("Total payouts: {} TON", formatAmount(_games[_currentGameIndex].sumPayouts)));
        }

        Terminal.print(0, stats);
    }

    function showRollSummary() public {
        checkBet();

        string summary = "Bet setup\n";
        summary.append(format("Amount: {} TON\n", formatAmount(_betAmount)));
        if (_isFirst) {
            summary.append("Dice that wins: 1st\n");
        } else {
            summary.append("Dice that wins: 2nd\n");
        }

        Terminal.print(0, summary);
    }

    function checkBet() public {
        uint128 maxBet = getMaxBet(_currentGameIndex);
        if (_betAmount > maxBet) {
            Terminal.print(0, format("Your bet can't exceed maximum bet for this contract: {:t}\n", maxBet));
            _betAmount = maxBet;
        }

        uint128 minBet = getMinBet(_currentGameIndex);
        if (_betAmount < minBet) {
            _betAmount = minBet;
        }
    }

    //========================================
    // game menu functions
    function switchDice() public {
        _isFirst = ! _isFirst;
        startGameMenu();
    }

    function doubleTheBet() public {
        _betAmount = _betAmount * 2;
        startGameMenu();
    }

    function setTheBet() public {
        AmountInput.get(tvm.functionId(saveBet), "How many tokens to bet?", 9, getMinBet(_currentGameIndex), getMaxBet(_currentGameIndex));
    }

    function saveBet(uint128 value) public {
        _betAmount = value;
        startGameMenu();
    }

    //========================================
    // get bet range
    function getMaxBet(uint32 gameIndex) public view returns (uint128 maxBet) {
        maxBet = uint128(_games[gameIndex].balance / _games[gameIndex].maxBetDivider);
    }

    function getMinBet(uint32 gameIndex) public view returns (uint128 minBet) {
        minBet = _games[gameIndex].minBet;
    }

    //========================================
    // refresh dicegames balances
    function loadGamesBalances() public {
        // prepare json header
        string[] headers;
        headers.push("Content-Type: application/json");

        // request body
        uint32 i;
        string body = "{\"query\":\"query{accounts(filter:{id:{in:[";
        for (i = 0; i < _games.length; i++) {
            body.append(format("\\\"{}\\\"", _games[i].addr));
            if (i < _games.length - 1) {
                body.append(',');
            }
        }
        body.append("]}}){id,balance}}\"}");

        // actual request
        Network.post(tvm.functionId(parseAccountsResponse), getApiUrl(), headers, body);
    }

    function parseAccountsResponse(int32 statusCode, string content) public {
        require(statusCode == 200);
        if (content.byteLength() > 27) {
            Json.deserialize(tvm.functionId(parseAccountsJson), content);
        }
    }

    struct Accounts {
        AccountsData data;
    }
    struct AccountsData {
        Account[] accounts;
    }
    struct Account {
        address id;
        uint128 balance;
    }
    function parseAccountsJson(bool result, Accounts obj) public {
        require(result == true);

        uint32 i;
        uint32 j;
        for (i = 0; i < _games.length; i++) {
            for (j = 0; j < obj.data.accounts.length; j++) {
                if (_games[i].addr == obj.data.accounts[j].id) {
                    _games[i].balance = obj.data.accounts[j].balance;
                    break;
                }
            }
        }
    }

    //========================================
    // refresh dicegame stats
    function loadCurrentGameStats() public {
        // prepare json header
        string[] headers;
        headers.push("Content-Type: application/json");

        // request body
        string body = "{\"query\":\"query{aggregateMessages(filter:{src:{eq:\\\"";
        body.append(format("{}", _games[_currentGameIndex].addr));
        body.append("\\\"}}fields:[{field:\\\"value\\\",fn:MAX},{field:\\\"value\\\",fn:SUM}])}\"}");

        // actual request
        Network.post(tvm.functionId(parseStatsResponse), getApiUrl(), headers, body);
    }

    function parseStatsResponse(int32 statusCode, string content) public {
        require(statusCode == 200);
        if (content.byteLength() > 42) {
            Json.deserialize(tvm.functionId(parseStatsJson), content);
        }
    }

    struct Stats {
        StatsData data;
    }
    struct StatsData {
        uint128[] aggregateMessages;
    }
    function parseStatsJson(bool result, Stats obj) public {
        require(result == true);
        _games[_currentGameIndex].maxPayout = obj.data.aggregateMessages[0];
        _games[_currentGameIndex].sumPayouts = obj.data.aggregateMessages[1];
    }

    //========================================
    /// @notice Load current game balance via Sdk
    function loadCurrentGameBalance() public {
        Sdk.getBalance(tvm.functionId(saveGameBalance), _games[_currentGameIndex].addr);
    }

    function saveGameBalance(uint128 nanotokens) public {
        _games[_currentGameIndex].balance = nanotokens;
    }

    //========================================
    /// @notice Roll the dice
    function rollDice() public {
        checkBet();

        // check if user has a signbox
        if(_keyHandle == 0) {
            uint[] none;
            SigningBoxInput.get(tvm.functionId(saveKeyHandle), "Enter keys to sign your transactions.", none);

        } else {

            // call contract to roll the dice
            TvmCell payload = tvm.encodeBody(IDicegame.roll, _isFirst);
            IMultisig(_multisigAddress).sendTransaction {
                abiVer: 2,
                extMsg: true,
                sign: true,
                pubkey: 0x00,
                time: uint32(now),
                expire: 0,
                callbackId: tvm.functionId(onRollSuccess),
                onErrorId: tvm.functionId(onError),
                signBoxHandle: _keyHandle
            }(_games[_currentGameIndex].addr, _betAmount, true, 1, payload);
        }
    }

    function onRollSuccess() public {
        Terminal.print(0, "You can see your roll result in the message from Dicegame contract!");
        startGameMenu();
    }

    function saveKeyHandle(uint32 handle) public {
        _keyHandle = handle;
        rollDice();
    }

    //========================================
    /// @notice Select dicegame
    function selectDicegame() public {
        uint32 i;
        string gamesList = "";
        gamesList.append("Dicegames list:\n");
        for (i = 0; i < _games.length; i++) {
            gamesList.append(format("{}. Address: {}. ", i + 1, formatAddress(_games[i].addr)));
            gamesList.append(format("Min bet: {} TON. Max bet: ~{} TON.\n", formatAmount(getMinBet(i)), formatAmount(getMaxBet(i))));
        }
        Terminal.print(0, gamesList);
        Terminal.input(tvm.functionId(setDicegame), "Enter dicegame number:", false);
    }

    function setDicegame(string value) public {
        (uint256 num,) = stoi(value);
        if (num > 0 && num <= _games.length) {
            _currentGameIndex = uint32(num - 1);
        }
        _start();
    }

    //========================================
    /// @notice Select account
    function selectWallet() public {
        AddressInput.get(tvm.functionId(saveWallet), "Attach your multisignature wallet:");
    }
    function saveWallet(address value) public {
        _multisigAddress = value;
        startGameMenu();
    }

    //========================================
    /// @notice Returns list of interfaces used by DeBot.
    function getRequiredInterfaces() public override view returns (uint256[] interfaces) {
        return [Terminal.ID, Menu.ID, AddressInput.ID, AmountInput.ID, Sdk.ID, SigningBoxInput.ID, Network.ID];
    }

    //========================================
    /// @notice Basic Debot functions
    function getDebotInfo() public functionID(0xDEB) override view returns(
        string name, string version, string publisher, string key, string author,
        address support, string hello, string language, string dabi, bytes icon
    ) {
        name = "Dicegame Debot";
        version = "0.1.0";
        publisher = "";
        key = "Play the Game of Dice";
        author = "Dicegame Labs";
        support = address.makeAddrStd(0, 0);
        hello = "The Game of Dice is very simple.\nThere are two dices. Player can choose a winning dice and make a bet.\nIf player wins the contract transfers back twice as much as was the bet.\nThis Dicegame Debot is created to help you with the above.";
        language = "en";
        dabi = m_debotAbi.get();
        icon = _icon;
    }

    fallback() external pure {}

    //========================================
    /// @notice Misc functions
    function onError(uint32 sdkError, uint32 exitCode) public {
        Terminal.print(0, format("Sdk error {}. Exit code {}.", sdkError, exitCode));
        startGameMenu();
    }

    function setIcon(bytes icon) public onlyOwner {
        _icon = icon;
    }

    function tokens(uint128 nanotokens) private pure returns (uint64, uint64) {
        uint64 decimal = uint64(nanotokens / 1e9);
        uint64 float = uint64(nanotokens - (decimal * 1e9));
        return (decimal, float);
    }

    function getApiUrl() private view returns (string url) {
        url = "http://localhost/graphql";
        if (_network == NETWORK_TESTNET) {
            url = "https://net1.ton.dev/graphql";
        }
        if (_network == NETWORK_MAINNET) {
            url = "https://main.ton.dev/graphql";
        }
        return url;
    }

    function formatAddress(address addr) private pure returns (string formatted) {
        string stringAddr = format("{}", addr);
        formatted = format("{}····{}", stringAddr.substr(0, 4), stringAddr.substr(stringAddr.byteLength() - 4));
    }

    function formatAmount(uint128 amount) private pure returns (string formatted) {
        (uint64 amountDec, uint64 amountFloat) = tokens(amount);
        formatted = format("{}.{:02}", amountDec, amountFloat / 1e7);
    }
}
