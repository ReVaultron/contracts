// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.21;

/**
 * @title IHederaTokenService
 * @dev Interface for interacting with Hedera Token Service (HTS) precompiled contract
 * @notice HTS is available at address 0x167 on all Hedera networks
 */
interface IHederaTokenService {
    /**
     * @dev Associates the provided account with the provided token
     * @param account The account to be associated with the provided token
     * @param token The token to be associated with the provided account
     * @return responseCode The response code for the status of the request
     */
    function associateToken(
        address account,
        address token
    ) external returns (int32 responseCode);

    /**
     * @dev Associates the provided account with the provided tokens
     * @param account The account to be associated with the provided tokens
     * @param tokens The tokens to be associated with the provided account
     * @return responseCode The response code for the status of the request
     */
    function associateTokens(
        address account,
        address[] memory tokens
    ) external returns (int32 responseCode);

    /**
     * @dev Dissociates the provided account with the provided token
     * @param account The account to be dissociated from the provided token
     * @param token The token to be dissociated from the provided account
     * @return responseCode The response code for the status of the request
     */
    function dissociateToken(
        address account,
        address token
    ) external returns (int32 responseCode);

    /**
     * @dev Dissociates the provided account with the provided tokens
     * @param account The account to be dissociated from the provided tokens
     * @param tokens The tokens to be dissociated from the provided account
     * @return responseCode The response code for the status of the request
     */
    function dissociateTokens(
        address account,
        address[] memory tokens
    ) external returns (int32 responseCode);

    /**
     * @dev Transfers tokens where the calling account/contract is implicitly the first entry in the token transfer list
     * @param token The token to transfer to/from
     * @param sender The sender for the transaction
     * @param recipient The receiver of the transaction
     * @param amount Non-negative value to send. A negative value will result in a failure
     * @return responseCode The response code for the status of the request
     */
    function transferToken(
        address token,
        address sender,
        address recipient,
        int64 amount
    ) external returns (int32 responseCode);

    /**
     * @dev Transfers tokens where the calling account/contract is implicitly the first entry in the token transfer list
     * @param token The token to transfer to/from
     * @param sender The sender for the transaction
     * @param recipient The receiver of the transaction
     * @param amount Non-negative value to send. A negative value will result in a failure
     * @return responseCode The response code for the status of the request
     */
    function transferTokens(
        address token,
        address[] memory sender,
        address[] memory recipient,
        int64[] memory amount
    ) external returns (int32 responseCode);

    /**
     * @dev Allows spender to withdraw from your account multiple times, up to the value amount. If this function is called
     * again it overwrites the current allowance with value
     * @param token The Hedera token address to approve
     * @param spender The spender address
     * @param amount The amount of tokens that spender can transfer
     * @return responseCode The response code for the status of the request
     */
    function approve(
        address token,
        address spender,
        uint256 amount
    ) external returns (int32 responseCode);

    /**
     * @dev Returns the amount which spender is still allowed to withdraw from owner
     * @param token The Hedera token address
     * @param owner The owner of the tokens
     * @param spender The spender address
     * @return responseCode The response code for the status of the request
     * @return allowance The amount which spender is still allowed to withdraw from owner
     */
    function allowance(
        address token,
        address owner,
        address spender
    ) external returns (int32 responseCode, uint256 allowance);

    /**
     * @dev Returns the balance of the token for the specified account
     * @param token The token address
     * @param account The account address
     * @return responseCode The response code for the status of the request
     * @return balance The balance of the token for the specified account
     */
    function balanceOf(
        address token,
        address account
    ) external returns (int32 responseCode, int64 balance);

    /**
     * @dev Returns token custom fees
     * @param token The token address
     * @return responseCode The response code for the status of the request
     * @return fixedFees Set of fixed fees for token
     * @return fractionalFees Set of fractional fees for token
     * @return royaltyFees Set of royalty fees for token
     */
    function getTokenCustomFees(
        address token
    )
        external
        returns (
            int32 responseCode,
            FixedFee[] memory fixedFees,
            FractionalFee[] memory fractionalFees,
            RoyaltyFee[] memory royaltyFees
        );

    /**
     * @dev Query token info
     * @param token The token address
     * @return responseCode The response code for the status of the request
     * @return tokenInfo The token info for the token
     */
    function getTokenInfo(
        address token
    ) external returns (int32 responseCode, TokenInfo memory tokenInfo);

    /**
     * @dev Query token fungible info
     * @param token The token address
     * @return responseCode The response code for the status of the request
     * @return fungibleTokenInfo The token info for the token
     */
    function getFungibleTokenInfo(
        address token
    )
        external
        returns (
            int32 responseCode,
            FungibleTokenInfo memory fungibleTokenInfo
        );

    // Structs for token information
    struct FixedFee {
        int64 amount;
        address tokenId;
        bool useHbarsForPayment;
        bool useCurrentTokenForPayment;
        address feeCollector;
    }

    struct FractionalFee {
        int64 numerator;
        int64 denominator;
        int64 minimumAmount;
        int64 maximumAmount;
        bool netOfTransfers;
        address feeCollector;
    }

    struct RoyaltyFee {
        int64 numerator;
        int64 denominator;
        int64 amount;
        address tokenId;
        bool useHbarsForPayment;
        address feeCollector;
    }

    struct TokenInfo {
        HederaToken token;
        int64 totalSupply;
        bool deleted;
        bool defaultKycStatus;
        bool pauseStatus;
        FixedFee[] fixedFees;
        FractionalFee[] fractionalFees;
        RoyaltyFee[] royaltyFees;
        string ledgerId;
    }

    struct FungibleTokenInfo {
        HederaToken token;
        int32 decimals;
    }

    struct HederaToken {
        string name;
        string symbol;
        address treasury;
        string memo;
        bool tokenSupplyType;
        int64 maxSupply;
        bool freezeDefault;
        TokenKey[] tokenKeys;
        Expiry expiry;
    }

    struct TokenKey {
        uint256 keyType;
        KeyValue key;
    }

    struct KeyValue {
        bool inheritAccountKey;
        address contractId;
        bytes ed25519;
        bytes ECDSA_secp256k1;
        address delegatableContractId;
    }

    struct Expiry {
        int64 second;
        address autoRenewAccount;
        int64 autoRenewPeriod;
    }
}
