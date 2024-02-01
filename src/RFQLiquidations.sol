// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.19;

pragma solidity ^0.8.19;

import "./RFQPnl.sol";
import "./RFQTrade.sol";

//TODO: Unfinished/untested code.
    contract RFQLiquidations is  Initializable  {
    RFQTrade public rfq;
    RFQPnl public pnl;

    function initialize(address _rfqaddress, address _pnl) public initializer {
        rfq = RFQTrade(address(_rfqaddress));
        pnl = RFQPnl(address(_pnl));
    }

    
function flashDefaultAuction(uint256 _bContractId) public {
    bContract memory _bContract = rfq.getBContractMemory(_bContractId);
    bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
    require(_bContract.cancelTime + rfq.CANCEL_TIME_BUFFER() > block.timestamp);
    require(_bContract.state == _State.Liquidated);

    if (_bContract.initiator == _bContract.partyA) {
        uint256 owedAmount = rfq.getOwedAmount(_bContract.partyA, _bContract.partyB);
        require(rfq.getBalance(msg.sender) > owedAmount);

        // Update balances
        uint256 msgSenderBalance = rfq.getBalance(msg.sender) - owedAmount;
        rfq.setBalance(msg.sender, msgSenderBalance);

        uint256 partyABalance = rfq.getBalance(_bContract.partyA) + owedAmount;
        rfq.setBalance(_bContract.partyA, partyABalance);

        // Update owed amounts
        rfq.decreaseTotalOwedAmounts(_bContract.partyA, owedAmount);
        rfq.setOwedAmounts(_bContract.partyA, _bContract.partyB, 0);

        // Additional balance requirements
        uint256 requiredBalanceA = (_bOracle.initialMarginA + _bOracle.defaultFundA * rfq.AFFILIATION_SHARE()) * _bContract.price * _bContract.qty;
        require(rfq.getBalance(msg.sender) > requiredBalanceA);

        uint256 requiredBalanceB = (_bOracle.initialMarginB + _bOracle.defaultFundB + _bOracle.defaultFundA * (1e18 - rfq.AFFILIATION_SHARE())) * _bContract.price * _bContract.qty;
        require(rfq.getBalance(_bContract.partyB) > requiredBalanceB);

        // Update balances
        rfq.setBalance(_bContract.partyA, rfq.getBalance(_bContract.partyA) - requiredBalanceA);
        rfq.setBalance(_bContract.partyB, rfq.getBalance(_bContract.partyB) - requiredBalanceB);
        rfq.setBContractParty(msg.sender, _bContractId, true);

    } else {
        require(_bContract.initiator == _bContract.partyB, "wrong party");

        uint256 owedAmount = rfq.getOwedAmount(_bContract.partyB, _bContract.partyA);
        require(rfq.getBalance(msg.sender) > owedAmount);

        // Update balances
        uint256 msgSenderBalance = rfq.getBalance(msg.sender) - owedAmount;
        rfq.setBalance(msg.sender, msgSenderBalance);

        uint256 partyABalance = rfq.getBalance(_bContract.partyA) + owedAmount;
        rfq.setBalance(_bContract.partyA, partyABalance);

        // Update owed amounts
        rfq.decreaseTotalOwedAmounts(_bContract.partyA, owedAmount);
        rfq.setOwedAmounts(_bContract.partyB, _bContract.partyA, 0);

        // Additional balance requirements -- Don't understand this logic for requiredBalance
        uint256 requiredBalanceB = (_bOracle.initialMarginB + _bOracle.defaultFundB * rfq.AFFILIATION_SHARE()) * _bContract.price * _bContract.qty / 1e36;
        require(rfq.getBalance(msg.sender) > requiredBalanceB);

        uint256 requiredBalanceA = (_bOracle.initialMarginA + _bOracle.defaultFundA + _bOracle.defaultFundB * (1e18 - rfq.AFFILIATION_SHARE())) * _bContract.price * _bContract.qty;
        require(rfq.getBalance(_bContract.partyA) > requiredBalanceA);

        // Update balances
        rfq.setBalance(_bContract.partyB, rfq.getBalance(_bContract.partyB) - requiredBalanceB);
        rfq.setBalance(_bContract.partyA, rfq.getBalance(_bContract.partyA) - requiredBalanceA);
        rfq.setBContractParty(msg.sender, _bContractId, false); //fixed -- check whether this should be partyB
    }

    //emit flashDefaultAuctionEvent(msg.sender);
}

//LIQUIDATELEVEL
    function liquidateLevel( bContract memory _bContract, bOracle memory _bOracle, uint256 toPay, bool isA) private{
        uint256 ir = (((_bContract.interestRate * (block.timestamp - _bOracle.lastPriceUpdateTime) * _bContract.price * _bContract.qty) / 31536000) + _bOracle.defaultFundB ); //check if necessary
        if(isA){
            toPay -= ( ir + _bOracle.defaultFundA ) * rfq.AFFILIATION_SHARE() ; // not sure this way to pay affiliation is risk proof.
            // If there's remaining amount in balance for Party A
            if (rfq.getBalance(_bContract.partyA) >= 0) {
                if (toPay >= rfq.getBalance(_bContract.partyA)) {
                    toPay -= rfq.getBalance(_bContract.partyA);
                    rfq.setBalance(_bContract.partyA, 0);
                    //maybe we need to do something here
                } 
            }
            if (toPay >= (_bOracle.initialMarginA + _bOracle.defaultFundA)  * _bContract.price * _bContract.qty / 1e18) {
                uint256 oldBalanceB = rfq.getBalance(_bContract.partyB);
                oldBalanceB += rfq.payOwed((_bOracle.initialMarginB + _bOracle.defaultFundB + _bOracle.initialMarginA + _bOracle.defaultFundA) * _bContract.price * _bContract.qty / 1e18, _bContract.partyB);
                toPay -= (_bOracle.initialMarginA + _bOracle.defaultFundA)  * _bContract.price * _bContract.qty / 1e18;
                rfq.addToOwed(toPay, _bContract.partyA, _bContract.partyB);
            }
            else { // If enough to pay with initialMargin + defaultFund
                if (toPay <= _bOracle.initialMarginA * _bContract.price * _bContract.qty) { // If there remains initialMargin
                    uint256 oldBalanceA = rfq.getBalance(_bContract.partyA);
                    uint256 oldBalanceB = rfq.getBalance(_bContract.partyB);
                    oldBalanceA += rfq.payOwed(_bOracle.initialMarginA - toPay, _bContract.partyA);
                    oldBalanceB += rfq.payOwed(toPay + (_bOracle.initialMarginB + _bOracle.defaultFundB + _bOracle.defaultFundA) * _bContract.price / 1e18, _bContract.partyB); //check
                    //check if we should set
                    rfq.setBalance(_bContract.partyA, oldBalanceA);
                    rfq.setBalance(_bContract.partyB, oldBalanceB);

                }
                else{
                    uint256 oldBalanceB = rfq.getBalance(_bContract.partyB);
                    oldBalanceB += rfq.payOwed((_bOracle.initialMarginB + _bOracle.defaultFundB + _bOracle.initialMarginA + _bOracle.defaultFundA ) * _bContract.price / 1e18, _bContract.partyB);
                    rfq.setBalance(_bContract.partyB, oldBalanceB);
                }
            }
            rfq.payAffiliates((ir + _bOracle.defaultFundA ) * rfq.AFFILIATION_SHARE(), _bContract); //check 
        }
        else{
            toPay -= ( ir + _bOracle.defaultFundB ) * rfq.AFFILIATION_SHARE() ; // not sure this way to pay affiliation is risk proof.
            // If there's remaining amount in balance for Party A
            if (rfq.getBalance(_bContract.partyB) >= 0) {
                if (toPay >= rfq.getBalance(_bContract.partyB)) {
                    toPay -= rfq.getBalance(_bContract.partyB);
                    rfq.setBalance(_bContract.partyB, 0);
                } 
            }
            if (toPay >= (_bOracle.initialMarginB + _bOracle.defaultFundB)  * _bContract.price * _bContract.qty / 1e18) {
                uint256 oldBalanceA = rfq.getBalance(_bContract.partyA);
                oldBalanceA += rfq.payOwed((_bOracle.initialMarginA + _bOracle.defaultFundA + _bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.price * _bContract.qty / 1e18, _bContract.partyA);
                rfq.setBalance(_bContract.partyA, oldBalanceA);
                toPay -= (_bOracle.initialMarginB + _bOracle.defaultFundB)  * _bContract.price * _bContract.qty / 1e18;
                rfq.addToOwed(toPay, _bContract.partyB, _bContract.partyA);
            } 
            else { // If enough to pay with initialMargin + defaultFund
                if (toPay <= _bOracle.initialMarginA * _bContract.price * _bContract.qty) { // If there remains initialMargin
                    uint256 oldBalanceB = rfq.getBalance(_bContract.partyB);
                    uint256 oldBalanceA = rfq.getBalance(_bContract.partyA);
                    oldBalanceB += rfq.payOwed(_bOracle.initialMarginA - toPay, _bContract.partyB);
                    oldBalanceA += rfq.payOwed(toPay + (_bOracle.initialMarginA + _bOracle.defaultFundA + _bOracle.defaultFundB ) * _bContract.price, _bContract.partyA);
                    rfq.setBalance(_bContract.partyB, oldBalanceB);
                    rfq.setBalance(_bContract.partyA, oldBalanceA);
                }
                else{
                    uint256 oldBalanceA = rfq.getBalance(_bContract.partyA);
                    oldBalanceA += rfq.payOwed((_bOracle.initialMarginA + _bOracle.defaultFundA + _bOracle.initialMarginB + _bOracle.defaultFundB ) * _bContract.price / 1e18, _bContract.partyA);
                    rfq.setBalance(_bContract.partyA, oldBalanceA);
                }
            }
            rfq.payAffiliates((ir + _bOracle.defaultFundB ) * rfq.AFFILIATION_SHARE(), _bContract);
        }
        
        rfq.setBContractStateMemory(_bContract, _State.Liquidated);
        rfq.setBContractCancelTimeMemory(_bContract, block.timestamp);
        rfq.setBContractPriceMemory(_bContract, _bOracle.lastPrice);
        _bContract.price = _bOracle.lastPrice;   
        
         }

    function settleAndLiquidate(uint256 _bContractId) public{
        bContract memory _bContract = rfq.getBContractMemory(_bContractId);
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        require(_bContract.state == _State.Open);

        //settleBContractWithoutLiquidation(_bContract.pairContractId_A);
        //settleBContractWithoutLiquidation(_bContract.pairContractId_B);
        //Getting A PnL:
        (uint256 uPnlA, bool isNegativeA, uint256 fundingA) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);
        uint256 uPnlB = uPnlA;
        bool isNegativeB = !isNegativeA;
        if (isNegativeA){
            (uint256 dynamicImA, uint256 dynamicImB) = pnl.dynamicIm(_bContract, _bOracle);
            if (rfq.getBalance(_bContract.partyA) > uPnlA + dynamicImA){ //check these
                uint256 partyABalance = rfq.getBalance(_bContract.partyA);
                uint256 partyBBalance = rfq.getBalance(_bContract.partyB);
                partyABalance -= (uPnlA - (dynamicImA * _bOracle.lastPrice * _bContract.qty) / 1e18);//check these values
                partyBBalance += (uPnlB + (dynamicImB * _bOracle.lastPrice * _bContract.qty) / 1e18);
                rfq.setBalance(_bContract.partyA, partyABalance);
                rfq.setBalance(_bContract.partyB, partyBBalance);
                rfq.setBContractPrice(_bContractId, _bOracle.lastPrice);
                rfq.setBContractOpenTime(_bContractId, _bOracle.lastPriceUpdateTime);
            }
            else if (rfq.getBalance(_bContract.partyA) + (_bOracle.initialMarginA *  _bOracle.lastPrice * _bContract.qty / 1e18) > uPnlA ){ // case where IM can pay
                if ( msg.sender == _bContract.partyB ){ 
                    liquidateLevel(_bContract, _bOracle, uPnlA, true);
                }
            }
            else if ( rfq.getBalance(_bContract.partyA) + ( ( _bOracle.initialMarginA + _bOracle.defaultFundA ) *  _bOracle.lastPrice * _bContract.qty) > uPnlA ){ // case where im + df can pay
                liquidateLevel(_bContract, _bOracle, uPnlA, true);
            }
        }
        else{
            (uint256 dynamicImA, uint256 dynamicImB) = pnl.dynamicIm(_bContract, _bOracle);
            if (rfq.getBalance(_bContract.partyB) > uPnlB + dynamicImB){
                uint256 partyABalance = rfq.getBalance(_bContract.partyA);
                uint256 partyBBalance = rfq.getBalance(_bContract.partyB);
                //subtracting loss in PnL
                partyBBalance -= uPnlA;
                //refunding the old margin 
                partyBBalance += (_bOracle.initialMarginB + _bOracle.defaultFundB) * _bContract.price * _bContract.qty / 1e18;
                //subtracting the dynamicMargin
                partyBBalance -= (dynamicImB * _bContract.price * _bContract.qty) / 1e18;
                
                
                partyABalance += (uPnlA);
                partyABalance += (dynamicImA * _bOracle.lastPrice * _bContract.qty) / 1e18;//check these later
                rfq.setBalance(_bContract.partyA, partyABalance);
                rfq.setBalance(_bContract.partyB, partyBBalance);
                rfq.setBContractPrice(_bContractId, _bOracle.lastPrice);
                rfq.setBContractOpenTime(_bContractId, _bOracle.lastPriceUpdateTime);
            }
            else if ( rfq.getBalance(_bContract.partyB) + ( _bOracle.initialMarginB *  _bOracle.lastPrice * _bContract.qty / 1e18) > uPnlB ){ // case where IM can pay
                if ( msg.sender == _bContract.partyA ){ 
                    liquidateLevel(_bContract, _bOracle, uPnlB, false);
                }
            }
            else if ( rfq.getBalance(_bContract.partyB) + ( ( _bOracle.initialMarginB + _bOracle.defaultFundB ) *  _bOracle.lastPrice * _bContract.qty / 1e18) > uPnlB ) { // case where im + df can pay
                liquidateLevel(_bContract, _bOracle, uPnlB, false);
            }
        }
    }

    function settleBContractWithoutLiquidation(uint256 bContractId) external { //can be called normally to settle?
        bContract memory _bContract = rfq.getBContractMemory(bContractId);
        bOracle memory _bOracle = rfq.getBOracle(_bContract.oracleId);
        (uint256 uPnlA, bool isNegativeA, uint256 fundingA) = pnl.calculateuPnlPartyA(_bContract, _bOracle, _bOracle.lastPrice, _bContract.qty);
        uint256 uPnlB = uPnlA;
        bool isNegativeB = !isNegativeA;    
        if( _bContract.state == _State.Open && _bContract.openTime + rfq.GRACE_PERIOD() < block.timestamp ){
            if (isNegativeA && rfq.getBalance(_bContract.partyA) > uPnlA){
                uint256 partyABalance = rfq.getBalance(_bContract.partyA);
                uint256 partyBBalance = rfq.getBalance(_bContract.partyB);
                partyABalance -= uPnlA;
                partyBBalance += rfq.payOwed(uPnlB, _bContract.partyB); //check this
                rfq.setBalance(_bContract.partyA, partyABalance);
                rfq.setBalance(_bContract.partyB, partyBBalance);

                
                
            }
            else if(isNegativeB && rfq.getBalance(_bContract.partyB) > uPnlB){
                uint256 partyABalance = rfq.getBalance(_bContract.partyA);
                uint256 partyBBalance = rfq.getBalance(_bContract.partyB);
                partyABalance += rfq.payOwed(uPnlA, _bContract.partyA);
                partyBBalance -= uPnlB;
                rfq.setBalance(_bContract.partyA, partyABalance);
                rfq.setBalance(_bContract.partyB, partyBBalance);
            }

                rfq.setBContractPrice(bContractId, _bOracle.lastPrice);
                rfq.setBContractOpenTime(bContractId, _bOracle.lastPriceUpdateTime);

        }

}
}