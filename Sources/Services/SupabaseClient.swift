import Supabase
import Foundation

// Replace these with your actual Supabase project values from supabase.com → Settings → API
let supabase = SupabaseClient(
    supabaseURL: URL(string: "https://sgbszuimvqxzqvmgvyrn.supabase.co")!,
    supabaseKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InNnYnN6dWltdnF4enF2bWd2eXJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzYzODc1MjQsImV4cCI6MjA5MTk2MzUyNH0.Oy_GmvXoEYpnkXHhIciMkzH46jYt8aJOk1CdNUHc-RE"
)
