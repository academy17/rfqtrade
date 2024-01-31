// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "./BaseFunctionality.sol";

contract RFQQuotes is BaseFunctionality {

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
        uint256 _timeLockB,
        uint256 pairContractId
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
            _timeLockB,
            pairContractId
        );

        emit deployPriceFeedEvent(bOracleLength);
        bOracleLength++;
    }


    function openQuote( 
        bool isLong,
        uint256 bOracleId,
        uint256 price,
        uint256 qty,
        uint256 interestRate, 
        bool isAPayingAPR, 
        address frontEndAffiliate, 
        address frontEndAffiliateAffiliate
    ) public {
        require(getOpenPositionNumber(msg.sender) < MAX_OPEN_POSITIONS, "too many positions" ); //decrement
        require(qty * price > MIN_NOTIONAL, "must be higher than minimum notional");
        bOracle memory oracle = getBOracle(bOracleId);
        setbContractVariablesQuote(
            msg.sender,
            bContractLength, 
            bOracleId, 
            price, qty, 
            interestRate, 
            isAPayingAPR, 
            frontEndAffiliate, 
            frontEndAffiliateAffiliate);

        if(isLong)  {
            require(((oracle.initialMarginA + oracle.defaultFundA) * qty * price / 1e18) < getBalance(msg.sender), "Balance Error");//CHECK MATH
            uint256 oldBalance = getBalance(msg.sender);
            uint256 updatedBalance = oldBalance - ((oracle.initialMarginA + oracle.defaultFundA) * qty * price / 1e18);
            setBalance(msg.sender, updatedBalance);
            setBContractParty(msg.sender, bContractLength, true);
        }
        else  {
            require(((oracle.initialMarginB + oracle.defaultFundB) * qty * price / 1e18) < getBalance(msg.sender), "Balance Error");//CHECK MATH
            uint256 oldBalance = getBalance(msg.sender);
            uint256 updatedBalance = oldBalance - ((oracle.initialMarginB + oracle.defaultFundB) * qty * price / 1e18);
            setBalance(msg.sender, updatedBalance);
            setBContractParty(msg.sender, bContractLength, false);
        }
        /*
        emit openQuoteEvent(msg.sender, bContractLength, isLong, bOracleId, price, qty, interestRate, isAPayingAPR);
        incrementbContractLength;
        incrementOpenPositionNumber(msg.sender);
        */
    }

    function acceptQuote(
        uint256 _bContractId, 
        uint256 _acceptPrice, 
        address backendAffiliate
    ) public { 
        require(getOpenPositionNumber(msg.sender) < MAX_OPEN_POSITIONS, "too many positions" ); //decrement
        bContract memory _bContract = getBContractMemory(_bContractId);
        bOracle memory oracle = getBOracle(getBContractMemory(_bContractId).oracleId);
        if(_bContract.openTime == block.timestamp && _bContract.state == _State.Open) {
            if(_bContract.initiator == _bContract.partyA && _acceptPrice < _bContract.price) { 
                require(getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) * _bContract.price * _bContract.qty / 1e18), "BALANCE ERROR");
                uint256 oldPartyBRefund = getBalance(_bContract.partyB);
                oldPartyBRefund += ((oracle.initialMarginB + oracle.defaultFundB) * _bContract.price * _bContract.qty) / 1e18;
                setBalance(_bContract.partyB, oldPartyBRefund);
                setBContractParty(msg.sender, _bContractId, false);
                uint256 partyBNewBalance = getBalance(msg.sender);
                partyBNewBalance -= ((oracle.initialMarginB + oracle.defaultFundB) * _acceptPrice * _bContract.qty) / 1e18;
                setBalance(msg.sender, partyBNewBalance);
                uint256 partyABetterQuoteBalance = getBalance(_bContract.partyA);
                partyABetterQuoteBalance +=  ((1e18+(oracle.initialMarginA + oracle.defaultFundA)) * (_bContract.price - _acceptPrice ) * _bContract.qty / 1e18);
                setBalance(_bContract.partyA, partyABetterQuoteBalance);
                setBContractPrice(_bContractId, _acceptPrice);
                }
            else if(_bContract.initiator == _bContract.partyB && _acceptPrice > _bContract.price) { 
                require(getBalance(msg.sender) > (( oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18), "BALANCE TOO LOW");
                uint256 oldPartyARefund = getBalance(msg.sender);
                oldPartyARefund += (oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18; //issue, when we refund, we refund the newly accepted _price, need to find some way of storing oldPride.
                setBalance(_bContract.partyA, oldPartyARefund);
                setBContractParty(msg.sender, _bContractId, true);
                uint256 partyANewBalance = getBalance(msg.sender);
                partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) * _acceptPrice * _bContract.qty / 1e18;
                setBalance(msg.sender, partyANewBalance);
                uint256 partyBBetterQuoteBalance = getBalance(_bContract.partyB);
                partyBBetterQuoteBalance += (1e18-(oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18;
                setBalance(_bContract.partyB, partyBBetterQuoteBalance);
                setBContractPrice(_bContractId, _acceptPrice);
                }
            //emit acceptQuoteEvent(msg.sender, pairContractId, _acceptPrice);
        } else {
                require(_bContract.state == _State.Quote);
                if (_bContract.initiator == _bContract.partyA){
                    setBContractParty(msg.sender, _bContractId, false);
                    if(_acceptPrice < _bContract.price) {
                        require(getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18));
                        require(getBalance(msg.sender) > (((_bContract.price - _acceptPrice ) * _bContract.qty))) ; //check we have more than enough to settle instantly
                        uint256 partyBNewBalance = getBalance(msg.sender);
                        partyBNewBalance -= (oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18;
                        setBalance(msg.sender, partyBNewBalance);
                        uint256 partyABetterQuoteBalance = getBalance(_bContract.partyA);
                        partyABetterQuoteBalance += ((oracle.initialMarginA + oracle.defaultFundA)) * (_bContract.price - _acceptPrice ) * _bContract.qty / 1e18; //logic correction, its possible to get 2x profit if user settle instantly
                        setBalance(_bContract.partyA, partyABetterQuoteBalance);
                        setBContractPrice(_bContractId, _acceptPrice);
                    } else {
                        require(getBalance(msg.sender) > (( oracle.initialMarginB + oracle.defaultFundB) *_bContract.price * _bContract.qty / 1e18)); 
                        uint256 partyBNewBalance = getBalance(msg.sender);
                        partyBNewBalance -= (oracle.initialMarginB + oracle.defaultFundB) *_acceptPrice * _bContract.qty / 1e18;
                        setBalance(msg.sender, partyBNewBalance);
                    }
                }
                if (_bContract.initiator == _bContract.partyB){
                    setBContractParty(msg.sender, _bContractId, true);
                    if(_acceptPrice > _bContract.price) {
                        require(getBalance(_bContract.partyB) > ((oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18); //ensure p[b] jas enough collateral, offset by instant settlement
                        require(getBalance(msg.sender) > (((_acceptPrice - _bContract.price) * _bContract.qty))) ; //check we have more than enough to settle instantly
                        require(getBalance(msg.sender) > (( oracle.initialMarginA + oracle.defaultFundA) *_acceptPrice * _bContract.qty /1e18)); 
                        uint256 partyANewBalance = getBalance(msg.sender);
                        partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) *_acceptPrice * _bContract.qty / 1e18;
                        setBalance(msg.sender, partyANewBalance);
                        uint256 partyBBetterQuoteBalance = getBalance(_bContract.partyB);
                        partyBBetterQuoteBalance -= ((oracle.initialMarginB + oracle.defaultFundB)) * (_acceptPrice - _bContract.price ) * _bContract.qty / 1e18; //takes a little more from partyB
                        setBalance(_bContract.partyB, partyBBetterQuoteBalance);
                        setBContractPrice(_bContractId, _acceptPrice);
                    }
                    else {
                        require(getBalance(msg.sender) > ( ( oracle.initialMarginA + oracle.defaultFundA) *_bContract.price * _bContract.qty / 1e18)); 
                        uint256 partyANewBalance = getBalance(msg.sender);
                        partyANewBalance -= ( oracle.initialMarginA + oracle.defaultFundA) * _bContract.price * _bContract.qty / 1e18;
                        setBalance(msg.sender, partyANewBalance);
                    }
                }
                setBContractAffiliate(_bContractId, backendAffiliate);
                setBContractState(_bContractId, _State.Open);
                setBContractOpenTime(_bContractId, block.timestamp);
                incrementOpenPositionNumber(msg.sender);
                _bContract.backEndAffiliate = backendAffiliate;
                //emit acceptQuoteEvent(msg.sender, _bContractId, pairContractId, _acceptPrice);
        }
    }

    function partialAcceptQuote(
        uint256 _bContractId, 
        uint256 fillAmount, 
        address backEndAffiliate
        ) public {
        bContract memory _bContract = getBContractMemory(_bContractId);
        bOracle memory _bOracle = getBOracle(getBCloseQuotesLength());
        require(_bContract.state == _State.Quote);
        if (_bContract.initiator == _bContract.partyA) {
            require(getBalance(msg.sender) > ((_bOracle.initialMarginB + _bOracle.defaultFundB) *_bContract.price * fillAmount / 1e18), "invalid bal");
            uint256 oldBalanceB = getBalance(msg.sender);
            oldBalanceB -= (_bOracle.initialMarginB + _bOracle.defaultFundB) *_bContract.price * fillAmount / 1e18;
            setBContractParty(msg.sender, _bContractId, false);
            setBalance(msg.sender, oldBalanceB);
            incrementbContractLength();//newContract.partyA = _bContract.partyA;
            setBContractParty(_bContract.partyA, getBContractLength(), true);
            uint256 newBalanceA = getBalance(_bContract.partyA);
            newBalanceA += (_bOracle.initialMarginA + _bOracle.defaultFundA) * _bContract.price * fillAmount / 1e18;
            setBalance(_bContract.partyA, newBalanceA);
            setbContractVariablesQuote(
            _bContract.partyA,
            getBContractLength(), 
            _bContract.oracleId, 
            _bContract.price, 
            _bContract.qty - fillAmount, 
            _bContract.interestRate,
            _bContract.isAPayingAPR,
            _bContract.frontEndAffiliate,
            _bContract.frontEndAffiliateAffiliate);
            setBContractAffiliate(_bContractId, backEndAffiliate);
            setBContractState(_bContractId, _State.Open);
            setBContractState(getBContractLength(), _State.Quote);
        }
        if (_bContract.initiator == _bContract.partyB){
            require(getBalance(msg.sender) > (( _bOracle.initialMarginA + _bOracle.defaultFundA) *_bContract.price * fillAmount / 1e18), "invalid bal"); 
            uint256 oldBalanceA = getBalance(msg.sender);
            oldBalanceA -= (_bOracle.initialMarginA + _bOracle.defaultFundA) *_bContract.price * fillAmount / 1e18;
            setBContractParty(msg.sender, _bContractId, true);
            setBalance(msg.sender, oldBalanceA);
            incrementbContractLength();
            setBContractParty(_bContract.partyB, getBContractLength(), false);
            uint256 newBalanceB = getBalance(_bContract.partyB);
            newBalanceB += (_bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.price * fillAmount / 1e18;
            setBalance(_bContract.partyB, newBalanceB);
            setbContractVariablesQuote(
            _bContract.partyB,
            getBContractLength(), 
            _bContract.oracleId, 
            _bContract.price, 
            _bContract.qty - fillAmount, 
            _bContract.interestRate,
            _bContract.isAPayingAPR,
            _bContract.frontEndAffiliate,
            _bContract.frontEndAffiliateAffiliate);
            setBContractAffiliate(_bContractId, backEndAffiliate);
            setBContractState(_bContractId, _State.Open);
            setBContractState(getBContractLength(), _State.Quote);
        }
        
        //_bContract.qty = fillAmount;
        //bCloseQuotesLength++; //unsafe?
        //incrementOpenPositionNumber(msg.sender); //we don't need to increment openPositionNumber because one was closed
        //emit partialAcceptQuoteEvent(msg.sender, _bContractId, fillAmount);
            
        // Finish 
        }

        function cancelOpenQuote(uint256 _bContractId) public {
        bContract memory _bContract = getBContractMemory(_bContractId);
        bOracle memory _bOracle = getBOracle(_bContract.oracleId);
        require( _bContract.state == _State.Open);
        if(msg.sender == _bContract.partyA ){
            uint256 oldBalanceA = getBalance(msg.sender);
            oldBalanceA += (_bOracle.initialMarginA + _bOracle.defaultFundA) * _bContract.qty * _bContract.price / 1e18;
            setBalance(_bContract.partyA, oldBalanceA);
            decrementOpenPositionNumber(msg.sender);
            setBContractState(_bContractId, _State.Closed);
        }
        else{
        require( msg.sender == _bContract.partyB );
            uint256 oldBalanceB = getBalance(msg.sender);
            oldBalanceB += (_bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.qty * _bContract.price / 1e18;
            setBalance(_bContract.partyB, oldBalanceB);
            decrementOpenPositionNumber(msg.sender);
            setBContractState(_bContractId, _State.Closed);
        }
        //emit cancelOpenQuoteEvent(bContractId );
    }

    function cancelOpenCloseQuoteBatch(uint256 bCloseQuoteId) public { //@audit visibility - FIXED
        bCloseQuote memory quote = getBCloseQuote(bCloseQuoteId);
        require(msg.sender == quote.initiator);
        require(quote.state == _State.Quote, "Quote must be in Quote state");
        for (uint256 i = 0; i < quote.bContractIds.length; i++) { //audit-possibly-unsafe
            setBContractState(quote.bContractIds[i], _State.Canceled);
        }
        //emit cancelOpenCloseQuoteContractIdEvent(bContractIds[]);
    }

    function cancelOpenCloseQuoteOrder(uint256 _bContractId) public { //@audit visibility - FIXED
        bCloseQuote memory quote = getBCloseQuote(_bContractId);
        require(msg.sender == quote.initiator);
        require(quote.state != _State.Canceled, "Quote already canceled");
        quote.state = _State.Canceled;
        //emit cancelOpenCloseQuoteContractIdEvent(_bContractId);
    }



}