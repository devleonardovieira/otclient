// Utility helpers for HMAC signing used across HTTP modules
#pragma once

#include <string>
#include <random>
#include <cstdlib>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <openssl/sha.h>

namespace http_hmac {
    inline constexpr const char* DEFAULT_SITE_API_KEY = "6f8d9c2a1b7e4d3f9a0c5e7b2d6f1a3c8e9b0d4f2a6c7e5b1d3f9a2c4e6b8d0f"; // 256-bit hex

    inline std::string toHex(const unsigned char* data, size_t len) {
        static const char* hex = "0123456789abcdef";
        std::string out;
        out.resize(len * 2);
        for (size_t i = 0; i < len; ++i) {
            unsigned char c = data[i];
            out[i*2] = hex[(c >> 4) & 0xF];
            out[i*2 + 1] = hex[c & 0xF];
        }
        return out;
    }

    inline std::string sha256Hex(const std::string& s) {
        unsigned char digest[SHA256_DIGEST_LENGTH];
        SHA256(reinterpret_cast<const unsigned char*>(s.data()), s.size(), digest);
        return toHex(digest, sizeof(digest));
    }

    inline std::string hmacSha256Hex(const std::string& key, const std::string& data) {
        unsigned int len = 0;
        unsigned char* h = HMAC(EVP_sha256(), key.data(), (int)key.size(),
                                reinterpret_cast<const unsigned char*>(data.data()), (int)data.size(),
                                nullptr, &len);
        if (!h || len == 0) return std::string();
        return toHex(h, len);
    }

    inline std::string randomNonceHex(size_t bytes = 16) {
        std::random_device rd;
        std::uniform_int_distribution<int> dist(0, 255);
        std::string buf;
        buf.resize(bytes);
        for (size_t i = 0; i < bytes; ++i) buf[i] = static_cast<char>(dist(rd));
        return sha256Hex(buf).substr(0, bytes * 2); // hex length = bytes*2
    }

    inline std::string getDefaultSiteApiKey() {
        const char* env = std::getenv("SITE_API_KEY");
        if (env && *env) return std::string(env);
        return std::string(DEFAULT_SITE_API_KEY);
    }
}

