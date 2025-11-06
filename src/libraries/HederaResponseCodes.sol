// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/**
 * @title HederaResponseCodes
 * @dev Library containing response codes from Hedera Token Service operations
 * @notice These codes are returned by HTS precompiled contract at 0x167
 */
library HederaResponseCodes {
    // Success response code
    int32 internal constant SUCCESS = 22;

    // Common error codes
    int32 internal constant INVALID_TOKEN_ID = 167;
    int32 internal constant INVALID_ACCOUNT_ID = 170;
    int32 internal constant INSUFFICIENT_TOKEN_BALANCE = 172;
    int32 internal constant TOKEN_NOT_ASSOCIATED_TO_ACCOUNT = 173;
    int32 internal constant TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT = 175;
    int32 internal constant INVALID_SIGNATURE = 176;
    int32 internal constant INVALID_TRANSACTION = 177;
    int32 internal constant INSUFFICIENT_TX_FEE = 180;
    int32 internal constant ACCOUNT_IS_TREASURY = 184;
    int32 internal constant TOKEN_ID_REPEATED_IN_TOKEN_LIST = 186;
    int32 internal constant TOKEN_TRANSFER_LIST_SIZE_LIMIT_EXCEEDED = 187;
    int32 internal constant INVALID_TOKEN_TRANSFER_LIST = 189;
    int32 internal constant EMPTY_TOKEN_TRANSFER_BODY = 190;
    int32 internal constant INVALID_EXPIRATION_TIME = 191;
    int32 internal constant INVALID_ZERO_BYTE_IN_STRING = 192;
    int32 internal constant INVALID_AUTORENEW_ACCOUNT = 193;
    int32 internal constant AUTORENEW_ACCOUNT_NOT_ALLOWED = 194;
    int32 internal constant INVALID_RENEWAL_PERIOD = 195;
    int32 internal constant ACCOUNT_EXPIRED_AND_PENDING_REMOVAL = 196;
    int32 internal constant INVALID_TOKEN_MAX_SUPPLY = 197;
    int32 internal constant INVALID_TOKEN_NFT_SERIAL_NUMBER = 198;
    int32 internal constant INVALID_NFT_ID = 199;
    int32 internal constant METADATA_TOO_LONG = 200;
    int32 internal constant BATCH_SIZE_LIMIT_EXCEEDED = 201;
    int32 internal constant INVALID_QUERY_RANGE = 202;
    int32 internal constant FRACTION_DIVIDES_BY_ZERO = 203;
    int32 internal constant INSUFFICIENT_PAYER_BALANCE_FOR_CUSTOM_FEE = 204;
    int32 internal constant CUSTOM_FEES_LIST_TOO_LONG = 205;
    int32 internal constant INVALID_CUSTOM_FEE_COLLECTOR = 206;
    int32 internal constant INVALID_TOKEN_ID_IN_CUSTOM_FEES = 207;
    int32 internal constant TOKEN_NOT_ASSOCIATED_TO_FEE_COLLECTOR = 208;
    int32 internal constant TOKEN_MAX_SUPPLY_REACHED = 209;
    int32 internal constant SENDER_DOES_NOT_OWN_NFT_SERIAL_NO = 210;
    int32 internal constant CUSTOM_FEE_NOT_FULLY_SPECIFIED = 211;
    int32 internal constant CUSTOM_FEE_MUST_BE_POSITIVE = 212;
    int32 internal constant TOKEN_HAS_NO_FEE_SCHEDULE_KEY = 213;
    int32 internal constant CUSTOM_FEE_OUTSIDE_NUMERIC_RANGE = 214;
    int32 internal constant ROYALTY_FRACTION_CANNOT_EXCEED_ONE = 215;
    int32 internal constant FRACTIONAL_FEE_MAX_AMOUNT_LESS_THAN_MIN_AMOUNT =
        216;
    int32 internal constant CUSTOM_SCHEDULE_ALREADY_HAS_NO_FEES = 217;
    int32 internal constant CUSTOM_FEE_DENOMINATION_MUST_BE_FUNGIBLE_COMMON =
        218;
    int32
        internal
        constant CUSTOM_FRACTIONAL_FEE_ONLY_ALLOWED_FOR_FUNGIBLE_COMMON = 219;
    int32 internal constant INVALID_CUSTOM_FEE_SCHEDULE_KEY = 220;
    int32 internal constant INVALID_TOKEN_MINT_METADATA = 221;
    int32 internal constant INVALID_TOKEN_BURN_METADATA = 222;
    int32 internal constant CURRENT_TREASURY_STILL_OWNS_NFTS = 223;
    int32 internal constant ACCOUNT_STILL_OWNS_NFTS = 224;
    int32 internal constant TREASURY_MUST_OWN_BURNED_NFT = 225;
    int32 internal constant ACCOUNT_DOES_NOT_OWN_WIPED_NFT = 226;
    int32
        internal
        constant ACCOUNT_AMOUNT_TRANSFERS_ONLY_ALLOWED_FOR_FUNGIBLE_COMMON =
            227;
    int32 internal constant MAX_NFTS_IN_PRICE_REGIME_HAVE_BEEN_MINTED = 228;
    int32 internal constant PAYER_ACCOUNT_DELETED = 229;
    int32 internal constant CUSTOM_FEE_CHARGING_EXCEEDED_MAX_RECURSION_DEPTH =
        230;
    int32 internal constant CUSTOM_FEE_CHARGING_EXCEEDED_MAX_ACCOUNT_AMOUNTS =
        231;
    int32 internal constant INSUFFICIENT_SENDER_ACCOUNT_BALANCE_FOR_CUSTOM_FEE =
        232;
    int32 internal constant SERIAL_NUMBER_LIMIT_REACHED = 233;
    int32
        internal
        constant CUSTOM_ROYALTY_FEE_ONLY_ALLOWED_FOR_NON_FUNGIBLE_UNIQUE = 234;
    int32 internal constant NO_REMAINING_AUTOMATIC_ASSOCIATIONS = 235;
    int32 internal constant EXISTING_AUTOMATIC_ASSOCIATIONS_EXCEED_GIVEN_LIMIT =
        236;
    int32
        internal
        constant REQUESTED_NUM_AUTOMATIC_ASSOCIATIONS_EXCEEDS_ASSOCIATION_LIMIT =
            237;
    int32 internal constant TOKEN_IS_PAUSED = 238;
    int32 internal constant TOKEN_HAS_NO_PAUSE_KEY = 239;
    int32 internal constant INVALID_PAUSE_KEY = 240;
    int32 internal constant FREEZE_UPDATE_FILE_DOES_NOT_EXIST = 241;
    int32 internal constant FREEZE_UPDATE_FILE_HASH_DOES_NOT_MATCH = 242;
    int32 internal constant NO_UPGRADE_HAS_BEEN_PREPARED = 243;
    int32 internal constant NO_FREEZE_IS_SCHEDULED = 244;
    int32 internal constant UPDATE_FILE_HASH_CHANGED_SINCE_PREPARE_UPGRADE =
        245;
    int32 internal constant FREEZE_START_TIME_MUST_BE_FUTURE = 246;
    int32 internal constant PREPARED_UPDATE_FILE_IS_IMMUTABLE = 247;
    int32 internal constant FREEZE_ALREADY_SCHEDULED = 248;
    int32 internal constant FREEZE_UPGRADE_IN_PROGRESS = 249;
    int32 internal constant UPDATE_FILE_ID_DOES_NOT_MATCH_PREPARED = 250;
    int32 internal constant UPDATE_FILE_HASH_DOES_NOT_MATCH_PREPARED = 251;
    int32 internal constant CONSENSUS_GAS_EXHAUSTED = 252;
    int32 internal constant REVERTED_SUCCESS = 253;
    int32 internal constant MAX_STORAGE_IN_PRICE_REGIME_HAS_BEEN_USED = 254;
    int32 internal constant INVALID_ALIAS_KEY = 255;
    int32 internal constant UNEXPECTED_TOKEN_DECIMALS = 256;
    int32 internal constant INVALID_PROXY_ACCOUNT_ID = 257;
    int32 internal constant INVALID_TRANSFER_ACCOUNT_ID = 258;
    int32 internal constant INVALID_FEE_COLLECTOR_ACCOUNT_ID = 259;
    int32 internal constant ALIAS_IS_IMMUTABLE = 260;
    int32 internal constant SPENDER_ACCOUNT_SAME_AS_OWNER = 261;
    int32 internal constant AMOUNT_EXCEEDS_TOKEN_MAX_SUPPLY = 262;
    int32 internal constant NEGATIVE_ALLOWANCE_AMOUNT = 263;
    int32 internal constant CANNOT_APPROVE_FOR_ALL_FUNGIBLE_COMMON = 264;
    int32 internal constant SPENDER_DOES_NOT_HAVE_ALLOWANCE = 265;
    int32 internal constant AMOUNT_EXCEEDS_ALLOWANCE = 266;
    int32 internal constant MAX_ALLOWANCES_EXCEEDED = 267;
    int32 internal constant EMPTY_ALLOWANCES = 268;
    int32 internal constant FUNGIBLE_TOKEN_IN_NFT_ALLOWANCES = 269;
    int32 internal constant NFT_IN_FUNGIBLE_TOKEN_ALLOWANCES = 270;
    int32 internal constant INVALID_ALLOWANCE_OWNER_ID = 271;
    int32 internal constant INVALID_ALLOWANCE_SPENDER_ID = 272;
    int32 internal constant REPEATED_SERIAL_NUMS_IN_NFT_ALLOWANCES = 273;
    int32 internal constant FUNGIBLE_TOKEN_IN_NFT_APPROVALS = 274;
    int32 internal constant NFT_IN_FUNGIBLE_TOKEN_APPROVALS = 275;
    int32 internal constant INVALID_TOKEN_NFT_SERIAL_NUMBER_RANGE = 276;

    /**
     * @dev Converts response code to human-readable string
     * @param responseCode The response code from HTS
     * @return message The human-readable message
     */
    function getResponseMessage(
        int32 responseCode
    ) internal pure returns (string memory message) {
        if (responseCode == SUCCESS) return "SUCCESS";
        if (responseCode == INVALID_TOKEN_ID) return "INVALID_TOKEN_ID";
        if (responseCode == INVALID_ACCOUNT_ID) return "INVALID_ACCOUNT_ID";
        if (responseCode == INSUFFICIENT_TOKEN_BALANCE)
            return "INSUFFICIENT_TOKEN_BALANCE";
        if (responseCode == TOKEN_NOT_ASSOCIATED_TO_ACCOUNT)
            return "TOKEN_NOT_ASSOCIATED_TO_ACCOUNT";
        if (responseCode == TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT)
            return "TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT";
        if (responseCode == INVALID_SIGNATURE) return "INVALID_SIGNATURE";
        if (responseCode == INSUFFICIENT_TX_FEE) return "INSUFFICIENT_TX_FEE";
        if (responseCode == TOKEN_IS_PAUSED) return "TOKEN_IS_PAUSED";
        if (responseCode == NO_REMAINING_AUTOMATIC_ASSOCIATIONS)
            return "NO_REMAINING_AUTOMATIC_ASSOCIATIONS";
        if (responseCode == AMOUNT_EXCEEDS_ALLOWANCE)
            return "AMOUNT_EXCEEDS_ALLOWANCE";
        if (responseCode == SPENDER_DOES_NOT_HAVE_ALLOWANCE)
            return "SPENDER_DOES_NOT_HAVE_ALLOWANCE";

        return "UNKNOWN_ERROR";
    }

    /**
     * @dev Checks if the response code indicates success
     * @param responseCode The response code from HTS
     * @return success True if the response code is SUCCESS
     */
    function isSuccess(
        int32 responseCode
    ) internal pure returns (bool success) {
        return responseCode == SUCCESS;
    }
}
