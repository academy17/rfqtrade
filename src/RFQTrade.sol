
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;


import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "pyth-sdk-solidity/IPyth.sol";
import "pyth-sdk-solidity/PythStructs.sol";
import "../src/LiquidationsFunctionality.sol";


contract RFQTrade is Initializable, OwnableUpgradeable, LiquidationsFunctionality {
    
    IERC20 public USDCToken;
    using SafeERC20 for IERC20;
    function initialize(address _oracleAddress, address _USDCToken) public initializer {
        __Ownable_init(msg.sender);
        oracleAddress = _oracleAddress;
        USDCToken = IERC20(_USDCToken);
        RFQTRADE_ADMIN = msg.sender;
    }

    //ADMIN FUNCTIONS

    //DEFAULT VARIABLES
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
    
//AFFILIATIONS
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


//@note PairContract Update

    function updatePriceDummy(uint256 bOracleId, uint256 price, uint256 time) public {
        bOracle storage oracle = bOracles[bOracleId];
        if (bOracles[bOracleId].oracleType == _Oracle.PairTrade) {
            bContract memory pairContract = bContracts[oracle.pairContractId];
            uint256 pairContractPrice = pairContract.price;
            oracle.lastPrice = oracle.lastPrice * 1e18 / pairContractPrice;
            oracle.lastPriceUpdateTime = time;
        } else {
            require(oracle.oracleType == _Oracle.Dummy);
            oracle.lastPrice = price;
            oracle.lastPriceUpdateTime = time;

        }
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
        USDCToken.safeTransferFrom(msg.sender, address(this), _amount); //audit:Safe?
        emit depositEvent(msg.sender, _amount);
    }


//WITHDRAWALS AND DEPOSITS
    function intiateWithdraw(uint256 _amount) public { 
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

//////////////////// New
    mapping ( address => mapping ( address => bool )) whitelistSettlement;
    mapping ( address => mapping ( address => uint256 )) sponsorAmount;

    // User sets sponsor requireemtns
    function updateSponsorParameters( uint256 amount, bool istrue, address target) external onlyOwner { 
        whitelistSettlement[msg.sender][target] = istrue;
        sponsorAmount[msg.sender][target] = amount;
    }

    // Sponsor settlement so an address is incentized to call in case of liquidation
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


}