// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";

enum _State {Quote, Open, Closed, GracePeriod, Canceled, Liquidated}
enum _Oracle {Pyth, Chainlink, Dummy, PairTrade}
/**
     * @dev Represents each bilateral contract
     * @param partyA partyA is always long, partyB is always short
     * @param interestRate 1e18 = 100%, 1e17 = 10% etc.
     * @param isAPayingAPR party that initiates the trade is paying APR
*/

struct bContract { 
    address partyA; 
    address partyB; 
    uint256 oracleId; 
    address initiator;
    uint256 price;
    uint256 qty;
    uint256 interestRate;
    bool isAPayingAPR;
    uint256 openTime;
    _State state;
    address frontEndAffiliate;
    address backEndAffiliate;
    address frontEndAffiliateAffiliate;
    uint256 cancelTime;
}

/**
     * @dev Represents each order to close a contract contract
     * @param limitOrStop if limitOrStop is non 0, then it's the quoteprice
*/
struct bCloseQuote {
    uint256[] bContractIds;
    uint256[] price;
    uint256[] qty;
    uint256[] limitOrStop; 
    address initiator; 
    uint256 expiration; 
    uint256 cancelTime;
    uint256 openTime; 
    _State state;
} 

/**
     * @dev Oracle contains prices and tracks margin requirements
     * @param pairContractId if its a pairContract, computes pnl differently.
*/
    struct bOracle{
        uint256 lastPrice;
        uint256 lastPriceUpdateTime; 
        uint256 maxDelay;
        bytes32 pythAddress;
        _Oracle oracleType;
        uint256 initialMarginA;
        uint256 initialMarginB;
        uint256 defaultFundA;
        uint256 defaultFundB;
        uint256 expiryA;
        uint256 expiryB;
        uint256 timeLockA; 
        uint256 timeLockB;
    }

//Storage//
contract RFQTrade is Initializable, OwnableUpgradeable {

    event payOwedEvent(address indexed target, uint256 amount);
    event addToOwedEvent(address indexed target, address receiver, uint256 amount);
    event claimOwedEvent(address indexed target, address receiver, uint256 amount);
    event setPairContractEvent(address indexed target,uint256 indexed bContractId, uint256 indexed pairContractId); 
    event deployPriceFeedEvent(uint256 indexed bOracleId);
    event depositEvent(address indexed target, uint256 amount);
    event intiateWithdrawEvent( address indexed target, uint256 amount);
    event withdrawEvent( address indexed target, uint256 amount);
    event cancelWithdrawEvent( address indexed target, uint256 amount);
    event openQuoteEvent( address indexed target,uint256 indexed bContractId, bool isLong, uint256 bOracleId, uint256 price, uint256 qty, uint256 interestRate, bool isAPayingAPR); 
    event acceptQuoteEvent( address indexed target, uint256 indexed bContractId, uint256 pairContractId, uint256 price); 
    event partialAcceptQuoteEvent( address indexed target, uint256 indexed bContractId, uint256 pairContractId, uint256 fillAmount);
    event openCloseQuoteEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256[] bOracleids, uint256[] price, uint256[] qty, uint256[] limitOrStop, uint256 expiration);
    event acceptCloseQuoteEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256 index, uint256 amount );
    event closeMarketEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256 index);
    event expirateBContractEvent(uint256 indexed bContractId);
    event cancelOpenQuoteEvent( uint256 indexed bContractId );
    event cancelOCloseQuoteEvent(uint256 indexed bContractId);
    event feeTierUpdatedEvent(uint256 FE_AFFILIATION, uint256 FE_AFFI_AFFILIATION, uint256 HB_AFFILIATION, uint256 RFQ_DAO_DF_EVENT);
    
    uint8 public MAX_OPEN_POSITIONS; 
    uint256 public CANCEL_PRE_DEFAULT_AUCTION_PERIOD;
    uint256 public MIN_NOTIONAL;
    uint256 public FEE_AMNT_BP;
    uint256 public BP = 1e18; //100%
    uint256 public FE_AFFILIATION; 
    uint256 public FE_AFFI_AFFILIATION;
    uint256 public HB_AFFILIATION;
    uint256 public RFQ_DAO_DF_EVENT;
    uint256 public AFFILIATION_SHARE  = 4e17;
    uint256 public GRACE_PERIOD ;
    uint256 public CANCEL_TIME_BUFFER;
    address public CHAINLINK_USDC_ADDRESS; 
    address public LIQUIDATIONS_CONTRACT;
    address public QUOTES_CONTRACT;
    address public RFQ_DAO;
    address public RFQTRADE_ADMIN;
    address public CLOSE_POSITIONS_CONTRACT;
    address private oracleAddress;
    address public uPnL;
    
    IERC20 public USDCToken;
    mapping(address => uint8) internal openPositionNumber;
    mapping(address => uint256) internal balances; 
    uint256 internal bOracleLength;
    mapping(uint256 => bOracle) internal bOracles;
    uint256 internal bContractLength;
    mapping(uint256 => bContract) internal bContracts;
    uint256 internal bCloseQuotesLength;
    mapping(uint256 => bCloseQuote) internal bCloseQuotes;
    mapping(address => mapping( address => uint256 )) internal owedAmounts;
    mapping(address => uint256 ) internal totalOwedAmounts;
    mapping(address => uint256 ) internal totalOwedAmountPaids;
    mapping( address => uint256 ) internal gracePeriodLockedWithdrawBalances;
    mapping( address => uint256 ) internal gracePeriodLockedTime;
    mapping( address => uint256 ) internal minimumOpenPartialFillNotional;
    mapping( address => uint256 ) internal sponsorReward;
    mapping ( address => mapping ( address => bool )) whitelistSettlement;
    mapping ( address => mapping ( address => uint256 )) sponsorAmount;


    using SafeERC20 for IERC20;
    function initialize(address _oracleAddress, address _USDCToken) public initializer {
        __Ownable_init(msg.sender);
        oracleAddress = _oracleAddress;
        USDCToken = IERC20(_USDCToken);
        RFQTRADE_ADMIN = msg.sender;
    }

    function deployPriceFeed(
        uint256 _maxDelay,
        _Oracle _oracleType,
        bytes32 _pythAddress,
        uint256 _initialMarginA,
        uint256 _initialMarginB,
        uint256 _defaultFundA,
        uint256 _defaultFundB,
        uint256 _expiryA,
        uint256 _expiryB,
        uint256 _timeLockA,
        uint256 _timeLockB
    ) public {
        require(_maxDelay > 0, "Max delay must be greater than 0");
       bOracles[bOracleLength] = bOracle(
            0,        
            block.timestamp,    
            _maxDelay,            
            _pythAddress,
            _oracleType,
            _initialMarginA,
            _initialMarginB,
            _defaultFundA,
            _defaultFundB,
            _expiryA,
            _expiryB,
            _timeLockA,
            _timeLockB
        );

        emit deployPriceFeedEvent(bOracleLength);
        bOracleLength++;
    }


    function setQuotesContract(address _quotesContract) external onlyOwner { 
        QUOTES_CONTRACT = _quotesContract;
    }

    function setLiquidationsContract(address _liquidationsContract) external onlyOwner { 
        LIQUIDATIONS_CONTRACT = _liquidationsContract;
    }

    function setClosePositionsContract(address _closePositions) external onlyOwner {
        CLOSE_POSITIONS_CONTRACT = _closePositions;
    }

    function setDefaultVariables(
        uint256 _minimumNotional,
        uint256 _feeAmountBasisPoints,
        uint8 _maxOpenPositions,
        uint256 _gracePeriod, 
        uint256 _cancelTimeBuffer
    ) external onlyOwner {
        MIN_NOTIONAL = _minimumNotional;
        FEE_AMNT_BP = _feeAmountBasisPoints;
        MAX_OPEN_POSITIONS = _maxOpenPositions;
        GRACE_PERIOD = _gracePeriod;
        CANCEL_TIME_BUFFER = _cancelTimeBuffer;
    }

    function updateAffiliation(
        uint256 _frontShare, 
        uint256 _affiliateShare, 
        uint256 _hedgerShare, 
        uint256 _daoShare
    ) external onlyOwner {
        require(_frontShare + _affiliateShare + _hedgerShare + _daoShare == 10 * 1e17, "Sum of all shares must be 100"); // 10 * 1e17 is total declared in test file
        FE_AFFILIATION = _frontShare;
        FE_AFFI_AFFILIATION = _affiliateShare;
        HB_AFFILIATION = _hedgerShare;
        RFQ_DAO_DF_EVENT = _daoShare;
        emit feeTierUpdatedEvent(FE_AFFILIATION, FE_AFFI_AFFILIATION, HB_AFFILIATION, RFQ_DAO_DF_EVENT);
    }


    function updatePriceDummy(uint256 bOracleId, uint256 price, uint256 time) public {
        bOracle storage oracle = bOracles[bOracleId];
        require(oracle.oracleType == _Oracle.Dummy);
        oracle.lastPrice = price;
        oracle.lastPriceUpdateTime = time;
    }

    function updatePricePyth(
        uint256 _oracleId, 
        bytes[] calldata _updateData
        ) public { 
        int64 price;
        uint256 time;
        if (bOracles[_oracleId].oracleType == _Oracle.Pyth) {
            IPyth pyth = IPyth(oracleAddress);
            uint feeAmount = pyth.getUpdateFee(_updateData);
            require(msg.sender.balance >= feeAmount, "Insufficient balance");
            pyth.updatePriceFeeds{value: feeAmount}(_updateData);
            PythStructs.Price memory pythPrice = pyth.getPrice(bOracles[_oracleId].pythAddress);
            price = (pythPrice.price);
            require(pythPrice.price >= 0, "Pyth price is zero");
            time = uint256(pythPrice.publishTime);
            require(bOracles[_oracleId].maxDelay < time, " Oracle input expired ");
            require((bOracles[_oracleId].lastPrice != int64ToUint256(price)), "if price is exact same do no update, market closed");
            bOracles[_oracleId].lastPrice = int64ToUint256(price); 
        }
        
    }


        function int64ToUint256(
        int64 value
        ) public pure returns (uint256) {
        require(value >= 0, "Cannot cast negative int64 to uint256");

        int256 intermediate = int256(value);
        uint256 convertedValue = uint256(intermediate);
 
        return convertedValue;
        }


    function deposit(
        uint256 _amount
        ) public {
        require(_amount > 0, "Deposit amount must be greater than 0");
        _amount = payOwed(_amount, address(this));
        balances[msg.sender] += _amount;
        USDCToken.safeTransferFrom(msg.sender, address(this), _amount); 
        emit depositEvent(msg.sender, _amount);
    }

    function initiateWithdraw(uint256 _amount) public { 
        require(balances[msg.sender] >= _amount, "Insufficient balance");
        gracePeriodLockedTime[msg.sender] = block.timestamp ;
        gracePeriodLockedWithdrawBalances[msg.sender] += _amount;
        balances[msg.sender] -= _amount;
        emit intiateWithdrawEvent( msg.sender, _amount );
    }
    
    function withdraw(uint256 _amount) public { 
        require(gracePeriodLockedWithdrawBalances[msg.sender] >= _amount, "Insufficient balance");
        require( gracePeriodLockedTime[msg.sender] + GRACE_PERIOD >= block.timestamp, "Too Early" );
        balances[msg.sender] = _amount;
        USDCToken.safeTransfer(msg.sender, _amount);
        emit withdrawEvent( msg.sender, _amount );
    }

    function cancelWithdraw(uint256 _amount) public {
        require(gracePeriodLockedWithdrawBalances[msg.sender] >= _amount, "Insufficient balance");
        gracePeriodLockedWithdrawBalances[msg.sender] -= _amount;
        balances[msg.sender] += _amount;
        emit cancelWithdrawEvent( msg.sender, _amount );
    }



    function updateSponsorParameters( uint256 amount, bool istrue, address target) external onlyOwner { 
        whitelistSettlement[msg.sender][target] = istrue;
        sponsorAmount[msg.sender][target] = amount;
    }

    function sponsorSettlement( address target, address receiver ) private { 
        if ( receiver == RFQ_DAO && whitelistSettlement[target][RFQ_DAO] == false){
                if ( balances[target] > sponsorAmount[target][RFQ_DAO] ){
                    balances[target] -= sponsorAmount[target][RFQ_DAO];
                    balances[RFQ_DAO] += sponsorAmount[target][RFQ_DAO];
                }
            }
        else if ( whitelistSettlement[target][receiver] == true){
            if ( balances[target] > sponsorAmount[target][receiver]){
                    balances[target] -= sponsorAmount[target][receiver];
                    balances[receiver] += sponsorAmount[target][receiver];
                }
            }
    }

    modifier onlyRFQContracts() {
        require(
            msg.sender == LIQUIDATIONS_CONTRACT ||
            msg.sender == QUOTES_CONTRACT ||
            msg.sender == CLOSE_POSITIONS_CONTRACT);
            _;

    }
    function getBCloseQuoteContractIds(uint256 bCloseQuoteId) public view returns(uint256[] memory) {
        bCloseQuote memory _bCloseQuote = bCloseQuotes[bCloseQuoteId];
        return _bCloseQuote.bContractIds;
    }

    function getBCloseQuotePrices(uint256 bCloseQuoteId) public view returns(uint256[] memory) {
        bCloseQuote memory _bCloseQuote = bCloseQuotes[bCloseQuoteId];
        return _bCloseQuote.price;
    }

    function getOpenPositionNumber(address user) public view returns (uint256) {
        return openPositionNumber[user];
    }

    function getBContractMemory(uint256 id) public view returns (bContract memory) {
            return bContracts[id];
    }

    function getBalance(address account) public view returns (uint256) {
            return balances[account];
    }

    function getBOracleLength() public view returns (uint256) {
        return bOracleLength;
    }
    
    function getBOracle(uint256 id) public view returns (bOracle memory) {
        return bOracles[id];
    }

    function getBContractLength() public view returns (uint256) {
        return bContractLength;
    }

    function getBContract(uint256 id) public view returns (bContract memory) {
        return bContracts[id];
    }

    function getBCloseQuotesLength() public view returns (uint256) {
        return bCloseQuotesLength;
    }

    function getBCloseQuote(uint256 id) public view returns (bCloseQuote memory) {
        return bCloseQuotes[id];
    }

    function getOwedAmount(address owner, address spender) public view returns (uint256) {
        return owedAmounts[owner][spender];
    }

    function getTotalOwedAmount(address addr) public view returns (uint256) {
        return totalOwedAmounts[addr];
    }

    function getTotalOwedAmountPaid(address addr) public view returns (uint256) {
        return totalOwedAmountPaids[addr];
    }

    function getGracePeriodLockedWithdrawBalance(address addr) public view returns (uint256) {
        return gracePeriodLockedWithdrawBalances[addr];
    }

    function getGracePeriodLockedTime(address addr) public view returns (uint256) {
        return gracePeriodLockedTime[addr];
    }

    function getMinimumOpenPartialFillNotional(address addr) public view returns (uint256) {
        return minimumOpenPartialFillNotional[addr];
    }

    function getSponsorReward(address addr) public view returns (uint256) {
        return sponsorReward[addr];
    }

    function incrementbCloseQuotes() public  {
        bCloseQuotesLength++;
    }

    function incrementbContractLength() external onlyRFQContracts  {
        bContractLength++;
    }

    function incrementOpenPositionNumber(address user) external onlyRFQContracts  {
        openPositionNumber[user]++;
    }

    function decrementOpenPositionNumber(address user) external onlyRFQContracts  {
        openPositionNumber[user]--;
    }

    function setBalance(address _party, uint256 _amount) external onlyRFQContracts {
        balances[_party] = _amount;
    }

    function setBContractParty(address _party, uint256 bContractID, bool isPartyA) external onlyRFQContracts {
            bContract storage newContract = bContracts[bContractID];
            if(isPartyA) {
                newContract.partyA = _party;
            } else {
                newContract.partyB = _party;
            }
    }

    function setBContractQuantity(uint256 bContractId, uint256 _qty) external onlyRFQContracts {
        bContract storage newContract = bContracts[bContractId];
        newContract.qty = _qty;
    }   


    function setBCloseQuoteQtyZero(uint256 bCloseQuoteId, uint256 index) external onlyRFQContracts { 
            bCloseQuote storage _bCloseQuote = bCloseQuotes[bCloseQuoteId];
            _bCloseQuote.qty[index] = 0;

    }

    function setBCloseQuoteState(uint256 bCloseQuoteId, _State state) external onlyRFQContracts { 
            bCloseQuote storage _bCloseQuote = bCloseQuotes[bCloseQuoteId];
            _bCloseQuote.state = state;

    }
    

    function setBContractAffiliate(uint256 bContractId, address _backEndAffiliate) external onlyRFQContracts {
        bContract storage newContract = bContracts[bContractId];
        newContract.backEndAffiliate = _backEndAffiliate;
    }

    function setBContractState(uint256 bContractId, _State newState) external onlyRFQContracts {
            bContract storage newContract = bContracts[bContractId];
            newContract.state = newState;
    }

    function setBContractPrice(uint256 bContractID, uint256 _price) external onlyRFQContracts {
            bContract storage newContract = bContracts[bContractID];
            newContract.price = _price;
    }

    function setBContractOpenTime(uint256 _bContractId, uint256 _openTime) external onlyRFQContracts {
        bContract storage newContract = bContracts[_bContractId];
        newContract.openTime = _openTime;
    }

    function setBContractStateMemory(bContract memory _bContract, _State newState) external onlyRFQContracts {
        
        _bContract.state = newState;
    }

    function setBContractCancelTimeMemory(bContract memory _bContract, uint256 _time) external onlyRFQContracts {
        _bContract.cancelTime = _time;
    }

    function setBContractPriceMemory(bContract memory _bContract, uint256 _price) external onlyRFQContracts{

        _bContract.price = _price;

    }


    function setbContractVariablesQuote(
        address initiator,
        uint256 bContractID,
        uint256 bOracleId,
        uint256 price,
        uint256 qty,
        uint256 interestRate, 
        bool isAPayingAPR, 
        address frontEndAffiliate, 
        address frontEndAffiliateAffiliate
    ) external onlyRFQContracts {
            bContract storage newContract = bContracts[bContractID];
            newContract.initiator = initiator;
            newContract.price = price;
            newContract.qty = qty;
            newContract.interestRate = interestRate;
            newContract.isAPayingAPR = isAPayingAPR;
            newContract.oracleId = bOracleId;
            newContract.state = _State.Quote;
            newContract.frontEndAffiliate = frontEndAffiliate;
            newContract.frontEndAffiliateAffiliate = frontEndAffiliateAffiliate;
            newContract.openTime = block.timestamp;
    }

    function setBContractCloseQuote(
        uint256[] memory _bContractIds,
        uint256[] memory _price, 
        uint256[] memory _qty, 
        uint256[] memory _limitOrStop, 
        address _initiator,
        uint256 _expiration
    ) external onlyRFQContracts {
        bCloseQuote storage newQuote = bCloseQuotes[bCloseQuotesLength];
        newQuote.bContractIds = _bContractIds;
        newQuote.price = _price;
        newQuote.qty = _qty;
        newQuote.limitOrStop = _limitOrStop;
        newQuote.initiator = _initiator;
        newQuote.expiration = _expiration;
        newQuote.cancelTime = 0;
        newQuote.openTime = block.timestamp;
        newQuote.state = _State.Quote;
        emit openCloseQuoteEvent(msg.sender, bCloseQuotesLength, _bContractIds, _price, _qty, _limitOrStop, _expiration);
        incrementbCloseQuotes();
    }

    function payOwed(uint256 amount, address target) public returns(uint256) {
        uint256 returnedAmount = 0;

        if (totalOwedAmounts[target] == 0) { 
            returnedAmount = amount;
        } else if (totalOwedAmounts[target] >= amount) { 
            totalOwedAmountPaids[target] += amount;
            totalOwedAmounts[target] -= amount;
        } else {
            returnedAmount = amount - totalOwedAmounts[target];
            totalOwedAmountPaids[target] = totalOwedAmounts[target];
            totalOwedAmounts[target] = 0;
        }

    emit payOwedEvent(target, returnedAmount);
    return returnedAmount;
}

    function payAffiliates(
        uint256 amount,
        bContract memory _bContract
        ) external  onlyRFQContracts { 
        balances[_bContract.frontEndAffiliate] += amount * FE_AFFILIATION;
        balances[_bContract.frontEndAffiliateAffiliate] += amount * FE_AFFI_AFFILIATION;
        balances[_bContract.backEndAffiliate] += amount * HB_AFFILIATION;
        balances[RFQ_DAO] += amount * RFQ_DAO_DF_EVENT;
    }


    function addToOwed(uint256 deficit, address target, address receiver) internal  { 
        owedAmounts[target][receiver] += deficit;
        totalOwedAmounts[target] += deficit;
        emit addToOwedEvent(target, receiver, deficit);
    }
    

    function claimOwed(address target, address receiver) public {
        uint256 owed = owedAmounts[target][receiver];
        uint256 paid = totalOwedAmountPaids[target];

    if (paid >= owed) {
        totalOwedAmounts[target] -= owed;
        totalOwedAmountPaids[target] -= owed;
    } else {
        uint256 remainingOwed = owed - paid;
        totalOwedAmounts[target] -= remainingOwed;
        totalOwedAmountPaids[target] = 0;
        owedAmounts[target][receiver] = remainingOwed;
        }

        balances[receiver] += owed;
        emit claimOwedEvent(target, receiver, owed);
        owedAmounts[target][receiver] = 0;
    }


    function setOwedAmounts(address partyA, address partyB, uint256 amountA) external onlyRFQContracts{
            owedAmounts[partyA][partyB] = amountA;
        }  


    function decreaseTotalOwedAmounts(address partyA, uint256 amount) external onlyRFQContracts {
            totalOwedAmounts[partyA] -= amount;
        }  


    


}