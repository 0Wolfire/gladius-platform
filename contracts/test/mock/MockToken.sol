pragma solidity ^0.4.15;

import "../../source/token/IToken.sol";
import "../../source/token/ManagedToken.sol";

/**
 * @title Mock Token for testing only
 *
 * #created 10/10/2017
 * #author Frank Bonnet
 */  
contract MockToken is ManagedToken {


    /**
     * Construct mock token
     */
    function MockToken(string _name, string _symbol, bool _locked) 
        ManagedToken(_name, _symbol, _locked) {}

    /**
     * Prevents the accidental sending of ether
     */
    function () payable {
        revert();
    }
}
