//SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import "hardhat/console.sol";

import "./ClaimUpgradable.sol";
import "./abstract/CTXEntityUpgradable.sol";
import "./abstract/ERC1155RolesTrackerUp.sol";
import "./abstract/Posts.sol";
import "./abstract/Escrow.sol";
import "./interfaces/ITask.sol";

/**
 * @title Task / Request for Product (RFP) Entity
 * @dev Version 1.1.0
 * [TODO] Support for different share withing roles
 * [TODO] Distribute config for different roles
 * [TODO] Protocol Treasury Donation
 */
contract TaskUpgradable is ITask
    , ClaimUpgradable
    , Escrow
    {

    //-- Storage


    //-- Functions

    /// ERC165 - Supported Interfaces
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(ITask).interfaceId || super.supportsInterface(interfaceId);
    }

    /// Initializer
    function initialize (
        address container,
        string memory name_, 
        string calldata uri_ 
    ) public override initializer {
        super.initialize(container, name_, uri_);
        symbol = "TASK";
        // _roleAssign(treasury, "donation", 1);    //TODO: Add Donation Config for Treasury? 
    }


    //** Wrappers

    /// Apply (Nominte Self)
    function application(string memory uri_) external override {
        nominate(getExtTokenId(msg.sender), uri_);
    }
    
    /// Accept Application (Assign Role)
    function acceptApplicant(uint256 sbtId) external override {
        roleAssignToToken(sbtId, "applicant");
    }
    
    //** Added Functionality

    /* Just use the Post function directly
    /// Deliver 
    function deliver(string calldata uri_) external override {
        post("applicant", getExtTokenId(msg.sender), uri_);
    }
    */

    /// Reject Delivery / Request for Changes
    function deliveryReject(uint256 sbtId, string calldata uri_) external override AdminOrOwner {
        //Rejection Event w/Details
        emit DeliveryRejected(_msgSender(), sbtId, uri_);
    }

    /// Approve Delivery (Close Case w/Positive Verdict)
    function deliveryApprove(uint256 sbtId) external override {
        //Validate Stage
        require(stage < DataTypes.ClaimStage.Closed , "STAGE:TOO_LATE");
        //Add as Subject
        roleAssignToToken(sbtId, "subject");
        //Push Forward to Stage:Execusion
        if(stage < DataTypes.ClaimStage.Execution){
            _setStage(DataTypes.ClaimStage.Execution);
        }
    }

    /// Execute Reaction
    /// @param tokens address of all tokens to be disbursed
    function stageExecusion(address[] memory tokens) public {
        //Validate Stage
        require(stage == DataTypes.ClaimStage.Execution , "STAGE:EXECUSION_ONLY");
        //Validate Stage Requirements
        require(uniqueRoleMembersCount("subject") > 0 , "NO_WINNERS_PICKED");
        //Push to Stage:Closed
        _setStage(DataTypes.ClaimStage.Closed);
        //Disburse
        disburse(tokens);
        //Emit Execusion Event
        emit Executed(_msgSender());
    }

    /// Withdraw -- Disburse all funds to participants
    /// @dev May be called by anyone at the appropriate stage
    /// @param tokens Since we don't know which contracts may hold a blance we need the consumer to request them directly
    function disburse(address[] memory tokens) public override {
        //Validate Stage
        // require(stage == DataTypes.ClaimStage.Execution || stage == DataTypes.ClaimStage.Closed , "STAGE:EXECUSION_OR_CLOSED");
        require(stage == DataTypes.ClaimStage.Closed , "STAGE:EXECUSION_OR_CLOSED");
        
        //Send to Subject(s)
        _splitAndSend("subject", tokens);
        /* MOVED to _splitAndSend()
        //Get members in roles (subjects)
        uint256[] memory sbts = uniqueRoleMembers("subject");
        
        //Disburse Native Token
        uint256 tokenBalanceNative = contractBalance(address(0));
        if (tokenBalanceNative > 0){
            _disburse(address(0), sbts, tokenBalanceNative/sbts.length);
        }

        //Disburse Any Additional ERC20 Token
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = contractBalance(tokens[i]);
            //Disburse ERC20 Tokens
            if (tokenBalance > 0){
                _disburse(tokens[i], sbts, tokenBalance/sbts.length);
            }
        }
        */
    }

    /// Cancel Task
    function cancel(string calldata uri_, address[] memory tokens) public override {
        //Cancelltaion Procedure
        stageCancel(uri_);
        //Return Funds to Creator
        refund(tokens);
    }

    /// Refund -- Send Tokens back to Task Creator
    function refund(address[] memory tokens) public override {
        //Validate Stage
        require(stage == DataTypes.ClaimStage.Cancelled , "STAGE:CANCELLED");
        //Send to Creator(s)
        _splitAndSend("creator", tokens);
    }

    /// Split funds between different recipients (TBD: by relative share)
    // _splitAndSend(uint256[] memory sbts, uint256 amount){
    function _splitAndSend(string memory role, address[] memory tokens) internal {
        //Get members in roles (subjects)
        uint256[] memory sbts = uniqueRoleMembers(role);
        
        //Disburse Native Token
        uint256 tokenBalanceNative = contractBalance(address(0));
        if (tokenBalanceNative > 0){
            _disburse(address(0), sbts, tokenBalanceNative/sbts.length);
        }

        //Disburse Any Additional ERC20 Token
        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 tokenBalance = contractBalance(tokens[i]);
            //Disburse ERC20 Tokens
            if (tokenBalance > 0){
                _disburse(tokens[i], sbts, tokenBalance/sbts.length);
            }
        }
    }

    /// Disburse Token to SBT Holders
    function _disburse(address token, uint256[] memory sbts, uint256 amount) internal {
        //Send Funds
        for (uint256 i = 0; i < sbts.length; i++) {
            if(token == address(0)){
                //Disburse Native Token
                _release(payable(_getAccount(sbts[i])), amount);
            }else{
                //Disburse ERC20 Token
                _releaseToken(token, _getAccount(sbts[i]), amount);
            }
        }
    }

}