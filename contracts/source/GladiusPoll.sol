pragma solidity ^0.4.15;

import "./token/IToken.sol";
import "./token/retriever/ITokenRetriever.sol";
import "../infrastructure/ownership/TransferableOwnership.sol";

/**
 * @title Gladius poll system
 *
 * #created 18/10/2017
 * #author Frank Bonnet
 */
contract GladiusPoll is TransferableOwnership, ITokenRetriever {

    struct Balance {
        uint gla;
        uint index;
    }

    struct Vote {
        uint datetime;
        bool support;
        uint index;
    }

    struct Proposal {
        uint createdTimestamp;
        uint supportingWeight;
        uint rejectingWeight;
        mapping(address => Vote) votes;
        address[] voteIndex;
        uint index;
    }

    // Settings
    uint constant VOTING_DURATION = 7 days;
    uint constant MIN_QUORUM = 5; // 5%

    // Alocated balances
    mapping (address => Balance) private allocated;
    address[] private allocatedIndex;

    // Proposals
    mapping(address => Proposal) private proposals;
    address[] private proposalIndex;

    // Token
    IToken private glaToken;


    /**
     * Require `_token` to be the glaToken
     *
     * @param _token The address to test against
     */
    modifier only_accepted_token(address _token) {
        require(_token == address(glaToken));
        _;
    }


    /**
     * Require that `_token` is not the glaToken
     *
     * @param _token The address to test against
     */
    modifier not_accepted_token(address _token) {
        require(_token != address(glaToken));
        _;
    }


    /**
     * Require that sender has more than zero tokens 
     */
    modifier only_token_holder() {
        require(allocated[msg.sender].gla > 0);
        _;
    }


    /**
     * Require `_proposedAddress` to have been proposed already
     *
     * @param _proposedAddress Address that needs to be proposed
     */
    modifier only_proposed(address _proposedAddress) {
        require(isProposed(_proposedAddress));
        _;
    }


    /**
     * Require that the voting period for the proposal has
     * not yet ended
     *
     * @param _proposedAddress Address that was proposed
     */
    modifier only_during_voting_period(address _proposedAddress) {
        require(now <= proposals[_proposedAddress].createdTimestamp + VOTING_DURATION);
        _;
    }


    /**
     * Require that the voting period for the proposal has ended
     *
     * @param _proposedAddress Address that was proposed
     */
    modifier only_after_voting_period(address _proposedAddress) {
        require(now > proposals[_proposedAddress].createdTimestamp + VOTING_DURATION);
        _;
    }


    /**
     * Require that the proposal is supported
     *
     * @param _proposedAddress Address that was proposed
     */
    modifier only_when_supported(address _proposedAddress) {
        require(isSupported(_proposedAddress, false));
        _;
    }
    

    /**
     * Construct the poll
     *
     * @param _glaToken The GLA utility token
     */
    function GladiusPoll(address _glaToken) {
        glaToken = IToken(_glaToken);
    }


    /**
     * Returns true if `_owner` has a balance allocated
     *
     * @param _owner The account that the balance is allocated for
     * @return True if there is a balance that belongs to `_owner`
     */
    function hasBalance(address _owner) public constant returns (bool) {
        return allocatedIndex.length > 0 && _owner == allocatedIndex[allocated[_owner].index];
    }


    /** 
     * Get the allocated GLA balance of `_owner`
     * 
     * @param _owner The address from which the allocated token balance will be retrieved
     * @return The allocated gla token balance
     */
    function balanceOf(address _owner) public constant returns (uint) {
        return allocated[_owner].gla;
    }


    /**
     * Returns true if `_proposedAddress` is already proposed
     *
     * @param _proposedAddress Address that was proposed
     * @return Whether `_proposedAddress` is already proposed 
     */
    function isProposed(address _proposedAddress) public constant returns (bool) {
        return proposalIndex.length > 0 && _proposedAddress == proposalIndex[proposals[_proposedAddress].index];
    }


    /**
     * Returns the how many proposals where made
     *
     * @return The amount of proposals
     */
    function getProposalCount() public constant returns (uint) {
        return proposalIndex.length;
    }


    /**
     * Propose a poll regarding `_proposedAddress` 
     *
     * @param _proposedAddress The proposed address 
     */
    function propose(address _proposedAddress) public only_owner {
        require(!isProposed(_proposedAddress));

        // Add proposal
        Proposal storage p = proposals[_proposedAddress];
        p.createdTimestamp = now;
        p.index = proposalIndex.push(_proposedAddress) - 1;
    }


    /**
     * Gets the voting duration, the amount of time voting 
     * is allowed
     *
     * @return Voting duration
     */
    function getVotingDuration() public constant returns (uint) {              
        return VOTING_DURATION;
    }


    /**
     * Gets the number of votes towards a proposal
     *
     * @param _proposedAddress The proposed address 
     * @return uint Vote count
     */
    function getVoteCount(address _proposedAddress) public constant returns (uint) {              
        return proposals[_proposedAddress].voteIndex.length;
    }


    /**
     * Returns true if `_account` has voted on a proposal
     *
     * @param _proposedAddress The proposed address 
     * @param _account The key (address) that maps to the vote
     * @return bool Whether `_account` has voted on the proposal
     */
    function hasVoted(address _proposedAddress, address _account) public constant returns (bool) {
        bool voted = false;
        if (getVoteCount(_proposedAddress) > 0) {
            Proposal storage p = proposals[_proposedAddress];
            voted = p.voteIndex[p.votes[_account].index] == _account;
        }

        return voted;
    }


    /**
     * Returns true if `_account` supported a proposal
     *
     * @param _proposedAddress The proposed address 
     * @param _account The key (address) that maps to the vote
     * @return bool Supported
     */
    function getVote(address _proposedAddress, address _account) public constant returns (bool) {
        return proposals[_proposedAddress].votes[_account].support;
    }


    /**
     * Allows a token holder to vote on a proposal
     *
     * @param _proposedAddress The proposed address 
     * @param _support True if supported
     */
    function vote(address _proposedAddress, bool _support) public only_proposed(_proposedAddress) only_during_voting_period(_proposedAddress) only_token_holder {    
        Proposal storage p = proposals[_proposedAddress];
        Balance storage b = allocated[msg.sender];
        
        // Register vote
        if (!hasVoted(_proposedAddress, msg.sender)) {
            p.votes[msg.sender] = Vote(
                now, _support, p.voteIndex.push(msg.sender) - 1);

            // Register weight
            if (_support) {
                p.supportingWeight += b.gla;
            } else {
                p.rejectingWeight += b.gla;
            }
        } else {
            Vote storage v = p.votes[msg.sender];
            if (v.support != _support) {

                // Register changed weight
                if (_support) {
                    p.supportingWeight += b.gla;
                    p.rejectingWeight -= b.gla;
                } else {
                    p.rejectingWeight += b.gla;
                    p.supportingWeight -= b.gla;
                }
            }

            v.support = _support;
            v.datetime = now;
        }
    }


    /**
     * Returns the current voting results for a proposal
     *
     * @param _proposedAddress The proposed address 
     * @return supported, rejected
     */
    function getVotingResult(address _proposedAddress) public constant returns (uint, uint) {      
        Proposal storage p = proposals[_proposedAddress];    
        return (p.supportingWeight, p.rejectingWeight);
    }


    /**
     * Returns true if the proposal is supported
     *
     * @param _proposedAddress The proposed address 
     * @param _strict If set to true the function requires that the voting period is ended
     * @return bool Supported
     */
    function isSupported(address _proposedAddress, bool _strict) public constant returns (bool) {        
        Proposal storage p = proposals[_proposedAddress];
        bool supported = false;

        if (!_strict || now > p.createdTimestamp + VOTING_DURATION) {
            var (support, reject) = getVotingResult(_proposedAddress);
            supported = support > reject;
            if (supported) {
                supported = support + reject >= glaToken.totalSupply() * MIN_QUORUM / 100;
            }
        }
        
        return supported;
    }


    /**
     * Request that GLA smart-contract transfers `_value` worth 
     * of tokens to this contract
     *
     * @param _value The value of tokens that we are depositing
     */
    function deposit(uint _value) public {
        require(_value > 0);
        address sender = msg.sender;
        
        // Retrieve allocated tokens
        if (!glaToken.transferFrom(sender, this, _value)) {
            revert();
        }
        
        // Allocate tokens
        if (!hasBalance(sender)) {
            allocated[sender] = Balance(
                0, allocatedIndex.push(sender) - 1);
        }

        Balance storage b = allocated[sender];
        b.gla += _value;

        // Increase weight
        _adjustWeight(sender, _value, true);
    }


    /**
     * Withdraw GLA tokens from the contract and reduce the 
     * owners weight accordingly
     * 
     * @param _value The amount of GLA tokens to withdraw
     */
    function withdraw(uint _value) public {
        Balance storage b = allocated[msg.sender];

        // Require sufficient balance
        require(b.gla >= _value);
        require(b.gla - _value <= b.gla);

        // Update balance
        b.gla -= _value;

        // Reduce weight
        _adjustWeight(msg.sender, _value, false);

        // Call external
        if (!glaToken.transfer(msg.sender, _value)) {
            revert();
        }
    }


    /**
     * Failsafe mechanism
     * 
     * Allows the owner to retrieve tokens from the contract that 
     * might have been send there by accident
     *
     * @param _tokenContract The address of ERC20 compatible token
     */
    function retrieveTokens(address _tokenContract) public only_owner not_accepted_token(_tokenContract) {
        IToken tokenInstance = IToken(_tokenContract);
        uint tokenBalance = tokenInstance.balanceOf(this);
        if (tokenBalance > 0) {
            tokenInstance.transfer(msg.sender, tokenBalance);
        }
    }


    /**
     * Don't accept eth 
     */
    function () payable {
        revert();
    }


    /**
     * Adjust voting weight in ongoing proposals on which `_owner` 
     * has already voted
     * 
     * @param _owner The owner of the weight
     * @param _value The amount of weight that is adjusted
     * @param _increase Indicated whethter the weight is increased or decreased
     */
    function _adjustWeight(address _owner, uint _value, bool _increase) private {
        for (uint i = proposalIndex.length; i > 0; i--) {
            Proposal storage p = proposals[proposalIndex[i - 1]];
            if (now > p.createdTimestamp + VOTING_DURATION) {
                break; // Last active proposal
            }

            if (hasVoted(proposalIndex[i - 1], _owner)) {
                if (p.votes[_owner].support) {
                    if (_increase) {
                        p.supportingWeight += _value;
                    } else {
                        p.supportingWeight -= _value;
                    }
                } else {
                    if (_increase) {
                        p.rejectingWeight += _value;
                    } else {
                        p.rejectingWeight -= _value;
                    }
                }
            }
        }
    }
}
