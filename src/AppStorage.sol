// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

enum _State {Quote, Open, Closed, GracePeriod, Canceled, Liquidated}
enum _Oracle {Pyth, Chainlink, Dummy, PairTrade}
/*
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";
*/
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
//Struct for Close Quote ( Limit Close )
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

//Struct for Oracle
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
        uint256 pairContractId;
    }

//Storage//
contract AppStorage {

    event payOwedEvent(address indexed target, uint256 amount);
    event addToOwedEvent(address indexed target, address receiver, uint256 amount);
    event claimOwedEvent(address indexed target, address receiver, uint256 amount);
    event setPairContractEvent(address indexed target,uint256 indexed bContractId, uint256 indexed pairContractId); 
    event deployPriceFeedEvent(uint256 indexed bOracleId);
    event depositEvent(address indexed target, uint256 amount);
    event intiateWithdrawEvent( address indexed target, uint256 amount);
    event withdrawEvent( address indexed target, uint256 amount);
    event cancelWithdrawEvent( address indexed target, uint256 amount);
    event openQuoteEvent( address indexed target,uint256 indexed bContractId, bool isLong, uint256 bOracleId, uint256 price, uint256 qty, uint256 interestRate, bool isAPayingAPR, uint256 pairContractId); //-- changed to bool
    event acceptQuoteEvent( address indexed target, uint256 indexed bContractId, uint256 pairContractId, uint256 price); //uint256 pairContractId
    event partialAcceptQuoteEvent( address indexed target, uint256 indexed bContractId, uint256 pairContractId, uint256 fillAmount);//uint256 pairContractId
    event openCloseQuoteEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256[] bOracleids, uint256[] price, uint256[] qty, uint256[] limitOrStop, uint256 expiration);
    event acceptCloseQuoteEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256 index, uint256 amount );
    event closeMarketEvent( address indexed target, uint256 indexed bCloseQuoteId, uint256 index);
    event expirateBContractEvent(uint256 indexed bContractId);
    event cancelOpenQuoteEvent( uint256 indexed bContractId );
    event cancelOpenCloseQuoteContractIdEvent(uint256 indexed bContractId);
    event cancelOCloseQuoteEvent(uint256 indexed bContractId);
    event feeTierUpdatedEvent(uint256 FE_AFFILIATION, uint256 FE_AFFI_AFFILIATION, uint256 HB_AFFILIATION, uint256 RFQ_DAO_DF_EVENT);
    
    uint8 internal MAX_OPEN_POSITIONS; 
    uint256 internal CANCEL_PRE_DEFAULT_AUCTION_PERIOD;
    uint256 internal MIN_NOTIONAL;
    uint256 internal FEE_AMNT_BP;
    uint256 internal BP = 1e18; //100%
    uint256 internal FE_AFFILIATION; 
    uint256 internal FE_AFFI_AFFILIATION;
    uint256 internal HB_AFFILIATION;
    uint256 internal RFQ_DAO_DF_EVENT;
    uint256 internal AFFILIATION_SHARE  = 4e17;
    uint256 internal GRACE_PERIOD ;
    uint256 internal CANCEL_TIME_BUFFER;
    address internal CHAINLINK_USDC_ADDRESS; 
    address internal LIQUIDATIONS_CONTRACT;
    address internal QUOTES_CONTRACT;
    address internal RFQ_DAO;
    address internal RFQTRADE_ADMIN;
    address internal CLOSE_POSITIONS;
    address internal oracleAddress;
    address internal uPnL;
    
    //IERC20 public USDCToken;
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

}