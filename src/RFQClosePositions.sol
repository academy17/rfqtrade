//ADD rfq.payOwed, AFFILIATES, PNL TO THIS
//NICE!
// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./RFQPnl.sol";
import "./RFQTrade.sol";


contract RFQClosePositions is  Initializable  {


    RFQTrade public rfq;
    RFQPnl public pnl;

    function initialize(address _rfqaddress, address _pnl) public initializer {
        rfq = RFQTrade(address(_rfqaddress));
        pnl = RFQPnl(address(_pnl));
    }

    function acceptCloseQuote( uint256 bCloseQuoteId, uint256 index, uint256 amount ) public {
        bCloseQuote memory _bCloseQuote  = rfq.getBCloseQuote(bCloseQuoteId);
        require(index < _bCloseQuote.bContractIds.length, "Index out of bounds");
        bContract memory _bContract = rfq.getBContractMemory(_bCloseQuote.bContractIds[index]); 
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        //require(_bCloseQuote.bContractIds[index] != 0, "quote cancelled"); //is this necessary?
        require((_bCloseQuote.state == _State.Quote && _bCloseQuote.expiration > block.timestamp ) || 
        ( _bCloseQuote.state == _State.Quote && ( _bCloseQuote.cancelTime + rfq.CANCEL_TIME_BUFFER()) > block.timestamp), "CLose quote expired.");
        if(_bCloseQuote.qty[index] >= _bContract.qty){ 
            amount = _bContract.qty;
        }
        else{
            amount = _bCloseQuote.qty[index];
        }
        //require( amount <= _bContract.qty + rfq.MIN_NOTIONAL());
        //require( amount >= rfq.MIN_NOTIONAL());
        if (_bCloseQuote.initiator == _bContract.partyA ) {
            require(msg.sender == _bContract.partyB, "wrong party");
            if (_bCloseQuote.limitOrStop[index] >0) { 
            require(_bOracle.lastPrice >= _bCloseQuote.limitOrStop[index], "error");
            (uint256 uPnlA, bool isNegative, uint256 fundingA) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bCloseQuote.price[index], amount);
            closePosition(_bCloseQuote.bContractIds[index], _bContract, _bOracle, uPnlA, true, amount);
            }
        } else if (_bCloseQuote.initiator == _bContract.partyB ){
            require( msg.sender == _bContract.partyA, "wrong party");
            if (_bCloseQuote.limitOrStop[index] >0) {
            require(_bOracle.lastPrice <= _bCloseQuote.limitOrStop[index], "limit or stop");
            (uint256 uPnlB, bool isNegativeB, uint256 fundingB) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bCloseQuote.price[index], amount);
            closePosition(_bCloseQuote.bContractIds[index], _bContract, _bOracle, uPnlB, false, amount); //reversing negative
            }
        }
        rfq.setBCloseQuoteQtyZero(bCloseQuoteId, index);
        //emit acceptCloseQuoteEvent( msg.sender, bCloseQuoteId, index, amount );
    }

function closeMarket(uint256 bCloseQuoteId, uint256 index) public {
        bCloseQuote memory _bCloseQuote  = rfq.getBCloseQuote(bCloseQuoteId);
        require(_bCloseQuote.state == _State.Quote, "incorrect state");
        require(index < _bCloseQuote.bContractIds.length, "Index out of bounds");
        bContract memory _bContract = rfq.getBContractMemory(_bCloseQuote.bContractIds[index]); 
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        require( _bCloseQuote.qty[index] <= _bContract.qty + rfq.MIN_NOTIONAL(), " amount too big"); //might give problems due to scaling
        //require( _bCloseQuote.qty[index] >= rfq.MIN_NOTIONAL(), " amount too small");
        require(_bContract.state == _State.Open, "Contract not open");
        require(block.timestamp - _bContract.openTime > _bOracle.maxDelay, "Price feed delay"); //changed to contract open time
        require( _bCloseQuote.initiator == msg.sender, "You are not the closeQuote Initiator");
        require( _bCloseQuote.limitOrStop[index] == 0, "order is not a limit order"); //0 = limit order
        require(_bCloseQuote.openTime + rfq.CANCEL_TIME_BUFFER() <= block.timestamp, "Give hedger time to open a limit order");
        //require(_bCloseQuote.bContractIds[index] != 0, "quote cancelled");//Caspar -- Again
        (uint256 uPnlA, bool isNegativeA, uint256 funding) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);
        if (msg.sender == _bContract.partyA){
            require( _bCloseQuote.price[index] > _bOracle.lastPrice, "incorrect price"); //price must always be larger?
            closePosition(_bCloseQuote.bContractIds[index], _bContract, _bOracle, uPnlA, true, _bCloseQuote.qty[index]);

        }
        else{
            require(msg.sender == _bContract.partyB);
            require( _bCloseQuote.price[index] > _bOracle.lastPrice);
            closePosition(_bCloseQuote.bContractIds[index], _bContract, _bOracle, uPnlA, false, _bCloseQuote.qty[index]);
        }
        rfq.setBCloseQuoteQtyZero(bCloseQuoteId, index);
        rfq.setBCloseQuoteState(bCloseQuoteId, _State.Closed);
        //emit closeMarketEvent( msg.sender, bCloseQuoteId, index);
    }

    function closePosition(uint256 _bContractId, bContract memory _bContract, bOracle memory _bOracle, uint256 toPay, bool isA, uint256 amount) private{ 
        require(_bOracle.maxDelay + _bOracle.lastPriceUpdateTime <= block.timestamp, "update price");
        if ( amount > _bContract.qty){
            amount = _bContract.qty;
        }
        
        (uint256 uPnlA, bool isNegativeA, uint256 fundingA) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);

        if(isNegativeA){
            require(rfq.getBalance(_bContract.partyA) >= toPay);
            uint256 oldBalanceA = rfq.getBalance(_bContract.partyA);
            oldBalanceA -= (toPay - (_bOracle.initialMarginA + _bOracle.defaultFundA) * amount * _bContract.price / 1e18);
            rfq.setBalance(_bContract.partyA, oldBalanceA);
            // @audit verifiy that toPay cannot be negative ( since it is a multiplier of toPay probably but I have a doubt )
            toPay -= (fundingA * rfq.AFFILIATION_SHARE() / 1e18);
            rfq.payAffiliates(fundingA * rfq.AFFILIATION_SHARE() / 1e18, _bContract);
            uint256 newBalanceB = rfq.getBalance(_bContract.partyB);
            newBalanceB += rfq.payOwed( toPay + ( _bOracle.initialMarginB + _bOracle.defaultFundB) * amount * _bContract.price / 1e18, _bContract.partyB);
            rfq.setBalance(_bContract.partyB, newBalanceB);
        }
        else{
            //if statement for ispayingAPR
            //trying without APR
            require(rfq.getBalance(_bContract.partyB) >= toPay, "balance error");
            uint256 oldBalanceB = rfq.getBalance(_bContract.partyB);
            oldBalanceB -= (toPay - (_bOracle.initialMarginB + _bOracle.defaultFundB) * amount * _bContract.price / 1e18);
            rfq.setBalance(_bContract.partyB, oldBalanceB);
            // @audit verifiy that toPay cannot be negative ( since it is a multiplier of toPay probably but I have a doubt )
            toPay -= (fundingA * rfq.AFFILIATION_SHARE() / 1e18) ;
            rfq.payAffiliates(fundingA * rfq.AFFILIATION_SHARE() / 1e18, _bContract); //check these params since I updated
            uint256 newBalanceA = rfq.getBalance(_bContract.partyA);
            newBalanceA += rfq.payOwed(( _bOracle.initialMarginA + _bOracle.defaultFundA) * amount * _bContract.price / 1e18 + toPay, _bContract.partyA);
            rfq.setBalance(_bContract.partyA, newBalanceA);
        }
        rfq.setBContractQuantity(_bContractId, amount);
        uint256 contractQuantity = _bContract.qty - amount;
        if (contractQuantity == 0) {
            rfq.decrementOpenPositionNumber(_bContract.partyA);
            rfq.decrementOpenPositionNumber(_bContract.partyB);
            rfq.setBContractState(_bContractId, _State.Closed);
            }

    }

    function expirateBContract( uint256 _bContractId) public { 
        bContract memory _bContract = rfq.getBContractMemory(_bContractId);
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        require ( _bOracle.maxDelay + _bContract.openTime < block.timestamp && _bContract.state == _State.Open, "incorrect time");
        (uint256 uPnlA, bool isNegativeA, uint256 fundingA) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);
        (uint256 uPnlB, bool isNegativeB, uint256 fundingB) = pnl.calculateuPnlPartyB(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);

        if (msg.sender == _bContract.partyA){
            require( _bContract.openTime + _bOracle.timeLockA > block.timestamp, "incorrect timestamp");
            closePosition(_bContractId, _bContract, _bOracle, uPnlA, true, _bContract.qty);
        }
        else{
            require(msg.sender == _bContract.partyB);
            require( _bContract.openTime + _bOracle.timeLockB > block.timestamp, "incorrect timestamp");
            closePosition(_bContractId, _bContract, _bOracle, uPnlB, false, _bContract.qty);
        }
        //emit expirateBContractEvent(_bContractId);
    }




}