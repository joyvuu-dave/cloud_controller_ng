require 'kubeclient'

module Clients
  class KubernetesClient

    attr_reader :client

    def initialize
      kubernetes_creds = VCAP::CloudController::Config.config.get(:kubernetes)
      # @kubernetes_creds = {}
#       # opi-service-account-token-hvv8t
#       auth_options = {
#         bearer_token: 'eyJhbGciOiJSUzI1NiIsImtpZCI6IiJ9.eyJpc3MiOiJrdWJlcm5ldGVzL3NlcnZpY2VhY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9uYW1lc3BhY2UiOiJjZi1zeXN0ZW0iLCJrdWJlcm5ldGVzLmlvL3NlcnZpY2VhY2NvdW50L3NlY3JldC5uYW1lIjoib3BpLXNlcnZpY2UtYWNjb3VudC10b2tlbi1odnY4dCIsImt1YmVybmV0ZXMuaW8vc2VydmljZWFjY291bnQvc2VydmljZS1hY2NvdW50Lm5hbWUiOiJvcGktc2VydmljZS1hY2NvdW50Iiwia3ViZXJuZXRlcy5pby9zZXJ2aWNlYWNjb3VudC9zZXJ2aWNlLWFjY291bnQudWlkIjoiNTE2MWJjZmEtZmYzMS0xMWU5LTlhM2UtNDIwMTBhODAwMTJkIiwic3ViIjoic3lzdGVtOnNlcnZpY2VhY2NvdW50OmNmLXN5c3RlbTpvcGktc2VydmljZS1hY2NvdW50In0.pbxZ39GC0aZ3WJUOa9FPDP39VRu4szx62z8X1jpTKVVIQfxMBI3nbcvIl2AapDkXMjrL47DOT8d6yMfvrkQsXNMRDi-aT3pKsUkeZWPYR_SQkfcqnfAtKC2Nixc0gN1nBQRfCgtXbUTz_fDUG9ymN4li2OWy4uFF2LlLO2BOs9SZ_Jla112P6iW2Y2P-PKrRwT94Ih2Stib3qPgn2p_qLtLT3xKVKElFHNLekMmFPH4dm3eU6gW0vuBqrSsq3GiaZuCwVKTV9i8o0gRCkkSCqQJQrG_PmfSphniIX_PqKD1TANC1C5DvHgjFccPvX2coPi7su28MF1Q8wGR2G2_a_w'
#       }
#       ssl_options = {
#         ca: '-----BEGIN CERTIFICATE-----
# MIIDDDCCAfSgAwIBAgIRAJQMlATS0l+7vksEc+5vcwAwDQYJKoZIhvcNAQELBQAw
# LzEtMCsGA1UEAxMkYWZkYTkxOTItNmQ1Mi00NzgxLWFmYTUtM2U2MWQwZDIzOGU2
# MB4XDTE5MTEwNDE3MjgxNloXDTI0MTEwMjE4MjgxNlowLzEtMCsGA1UEAxMkYWZk
# YTkxOTItNmQ1Mi00NzgxLWFmYTUtM2U2MWQwZDIzOGU2MIIBIjANBgkqhkiG9w0B
# AQEFAAOCAQ8AMIIBCgKCAQEA19bc86n/w8ZF8sUZCL57dX7FS+BPn1H0jjhmwF0q
# ySzocaO5/ZNlTPiPdDY4ttQZOa6eN1QVcobhcPuUjhwZGm4IZWFSZcGujIajRud/
# cckV0COgpUjP2NsrFabo5JAgq1m2zKE3gwIYP3LUbrsqdwxwBg0FWdEOGlTFh4HA
# oPhIhdQ5IuM/rjKClGLL+mllL2AHXO2FzU9txrwxNbqTwxmI6GgLjnNSzpnjcRi1
# yA8DtIYy95r6gE2/ACJw+Upwdi6JThn3wDzQlZbSlxyPeRxyvf3wZWdI4VjHesSk
# X2ZBU2geFblEKijKXBhrtbgykEMBE/uz6cgN5c39XtkxewIDAQABoyMwITAOBgNV
# HQ8BAf8EBAMCAgQwDwYDVR0TAQH/BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEA
# CfVqB3Xnd9p3CtRVvdWEVfZnw0tH6YWflF1QF5wnq9cKPuCDc0awtS92w7qL4KdG
# I/TcNv6C9sCV7T25vCaJ9lV3rL+sfGTZG5qsFdhRsnFxzQBBfcGwMTMyLionsRTL
# uwmh9XDOdL9L0IJisZPMeyWddJ7ZyVl4dMWyA5ijn1oDxOx4Y/CHPmh04XhNm4vf
# ATTpRZcMCekTZjHCMld/PvooneItMCdQmK7n9n7BBtl2q+6qv6UUmmJy11duuYHY
# apwjQnxVPGUj1qc1wT801CZmyJRxqvFFtX8NzBfaJgWmxSo3WWf6hRaqieWymdmj
# /HjZwgfvb/beOPQtfNe/Vw==
# -----END CERTIFICATE-----'
#       }
#
#       @kubernetes_creds[:host_url] = "https://35.224.201.11/api/"

      auth_options = {
        bearer_token: kubernetes_creds[:service_account][:token]
      }
      ssl_options = {
        ca: kubernetes_creds[:ca]
      }
      @client = Kubeclient::Client.new(
        kubernetes_creds[:url],
        'v1',
        auth_options: auth_options,
        ssl_options:  ssl_options
      )
    end
  end
end
