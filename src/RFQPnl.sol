//CLEAN UP
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./RFQTrade.sol";

contract RFQPnl is Initializable {

    RFQTrade public rfq;
    function initialize(address _rfq_address) public initializer {
        rfq = RFQTrade(_rfq_address);
    }

    function calculateuPnlPartyA(bContract memory _bContract, bOracle memory _bOracle, uint256 _price, uint256 amount)
    public
    view
    returns (uint256, bool, uint256)
{
    uint256 funding = (
        _bContract.interestRate * (block.timestamp - _bContract.openTime) * _bContract.price * amount
    ) / 31536000; 
    uint256 fundingNormalized = funding / 1e18;
    uint256 uPnl;
    bool isNegative = false;

    if (_price >= _bContract.price) {
        uPnl = (_price - _bContract.price) * amount;
        if (_bContract.isAPayingAPR) {
            if (uPnl > fundingNormalized) {
                uPnl -= fundingNormalized;
                isNegative = false;
            } else {
                uPnl = fundingNormalized - uPnl;
                isNegative = true;
            }
        } else {
            if (uPnl < fundingNormalized) {
                uPnl = fundingNormalized - uPnl;
                isNegative = false;
            } else {
                uPnl -= fundingNormalized;
                isNegative = true;
            }
        }
    } else {
        // _price < _bContract.price
        uPnl = (_bContract.price - _price) * amount;
        // Adjust for funding
        if (!_bContract.isAPayingAPR) {
            if (uPnl < fundingNormalized) {
                uPnl = fundingNormalized - uPnl;
                isNegative = false;
            } else {
                uPnl -= fundingNormalized;
                isNegative = true;
            }
        }
    }

    return (uPnl, isNegative, fundingNormalized);
}
    
function calculateuPnlPartyB(bContract memory _bContract, bOracle memory _bOracle, uint256 _price, uint256 amount)
    public
    view
    returns (uint256, bool, uint256)
{
    uint256 funding = (
            _bContract.interestRate * (block.timestamp - _bContract.openTime) * _bContract.price * amount
        ) / 31536000; 
    uint256 fundingNormalized = funding / 1e18;
    uint256 uPnl;
    bool isNegative = false;

    if (_price < _bContract.price) {
        uPnl = (_bContract.price - _price) * amount;
        if (!_bContract.isAPayingAPR) {
            if (uPnl > fundingNormalized) {
                uPnl -= fundingNormalized;
            } else {
                uPnl = fundingNormalized - uPnl;
                isNegative = true;
            }
        } 
    } else if (_price > _bContract.price) {
        uPnl = (_price - _bContract.price) * amount;
        if(_bContract.isAPayingAPR) {
            if(uPnl < fundingNormalized) {
                uPnl = fundingNormalized - uPnl;
                isNegative = false;
            }
            if(fundingNormalized < uPnl){
                uPnl -= fundingNormalized;
                isNegative = true;
            }
        }
    } else {
        if (!_bContract.isAPayingAPR) {
            uPnl = fundingNormalized; 
            isNegative = true;
        } else {
            uPnl = fundingNormalized; 
        }
    }

    return (uPnl, isNegative, fundingNormalized);
}

    function dynamicIm(bContract memory _bContract, bOracle memory _bOracle)
        external
        pure
        returns (uint256, uint256)
    {
        uint256 scaleFactor = 1e18;
        { 
        uint256 priceRatioA = _bContract.price * scaleFactor / _bOracle.lastPrice;
        uint256 dynamicImA = priceRatioA * (_bOracle.initialMarginA + _bOracle.defaultFundA) / 1e18;
        uint256 priceRatioB = _bOracle.lastPrice * scaleFactor / _bContract.price;
        uint256 dynamicImB = (_bOracle.initialMarginB + _bOracle.defaultFundB) * priceRatioB / 1e18;
        return(dynamicImA, dynamicImB);
        }
    }


}