import Foundation
import Supabase

let supabase = SupabaseClient(
    supabaseURL: SupabaseConfiguration.projectURL,
    supabaseKey: SupabaseConfiguration.anonKey,
    options: SupabaseClientOptions(
        auth: .init(redirectToURL: SupabaseConfiguration.authRedirectURL)
    )
)
