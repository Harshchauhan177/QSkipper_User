// Follow this setup guide to integrate the Deno language server with your editor:
// https://deno.land/manual/getting_started/setup_your_environment
// This enables autocomplete, go to definition, etc.

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // ── 1. Verify the caller's JWT ──────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ success: false, message: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Create a client with the caller's JWT to extract the authenticated user
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      console.error("❌ delete-account: Auth error —", userError?.message);
      return new Response(
        JSON.stringify({ success: false, message: "Invalid or expired session" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userId = user.id;
    console.log(`🗑️ delete-account: Starting deletion for user ${userId}`);

    // ── 2. Create admin client with service_role key ────────────────
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // ── 3. Process user data from tables ──────────────────────────────
    const GHOST_USER_UUID = "00000000-0000-0000-0000-000000000001";

    // 3a. Ensure the ghost user exists in auth.users (the FK target).
    //     Previous versions checked profiles — but the FK is on auth.users,
    //     so we must verify THERE. Also, createUser errors were swallowed.
    const { data: ghostAuthData } = await adminClient.auth.admin.getUserById(GHOST_USER_UUID);

    if (!ghostAuthData?.user) {
      console.log("ℹ️ delete-account: Ghost user not found in auth.users — creating…");
      const { error: createError } = await adminClient.auth.admin.createUser({
        id: GHOST_USER_UUID,
        email: "ghost@deleted.local",
        email_confirm: true,
        user_metadata: { username: "Deleted User", phone: "" },
      });

      if (createError) {
        console.error("❌ delete-account: Failed to create ghost auth user —", createError.message);
        return new Response(
          JSON.stringify({ success: false, message: `Cannot provision ghost user: ${createError.message}` }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }
      console.log("✅ delete-account: Ghost auth user created");
    } else {
      console.log("✅ delete-account: Ghost auth user already exists");
    }

    // Ensure ghost profile row exists (idempotent upsert, separate from auth check)
    const { error: ghostProfileError } = await adminClient
      .from("profiles")
      .upsert({
        id: GHOST_USER_UUID,
        username: "Deleted User",
        phone: "",
      }, { onConflict: "id" });

    if (ghostProfileError) {
      console.error("⚠️ delete-account: Ghost profile upsert failed —", ghostProfileError.message);
    } else {
      console.log("✅ delete-account: Ghost profile ensured");
    }

    // 3b. Reassign orders to the ghost user
    const { error: reassignError, count: reassignedCount } = await adminClient
      .from("orders")
      .update({ user_id: GHOST_USER_UUID })
      .eq("user_id", userId);

    if (reassignError) {
      console.error("❌ delete-account: Failed to reassign orders —", reassignError.message);
    } else {
      console.log(`✅ delete-account: Reassigned ${reassignedCount ?? "all"} orders to ghost user`);
    }

    // 3d. Reassign blocked_users — TWO FK columns
    const { error: blockedUserIdError } = await adminClient
      .from("blocked_users")
      .update({ user_id: GHOST_USER_UUID })
      .eq("user_id", userId);
    
    if (blockedUserIdError) {
      console.log("ℹ️ delete-account: blocked_users.user_id reassign —", blockedUserIdError.message);
    } else {
      console.log("✅ delete-account: blocked_users.user_id reassigned");
    }

    const { error: blockedByError } = await adminClient
      .from("blocked_users")
      .update({ blocked_by: GHOST_USER_UUID })
      .eq("blocked_by", userId);
      
    if (blockedByError) {
      console.log("ℹ️ delete-account: blocked_users.blocked_by reassign —", blockedByError.message);
    } else {
      console.log("✅ delete-account: blocked_users.blocked_by reassigned");
    }

    // 3e. Delete wallet_transactions
    const { error: walletTxError } = await adminClient
      .from("wallet_transactions")
      .delete()
      .eq("user_id", userId);
      
    if (walletTxError) {
      console.log("ℹ️ delete-account: wallet_transactions —", walletTxError.message);
    } else {
      console.log("✅ delete-account: Deleted wallet_transactions");
    }

    // 3f. Delete wallet (PK is 'id')
    const { error: walletError } = await adminClient
      .from("wallets")
      .delete()
      .eq("id", userId);

    if (walletError) {
      console.error("❌ delete-account: Failed to delete wallet —", walletError.message);
    } else {
      console.log("✅ delete-account: Deleted wallet");
    }

    // 3g. Delete profile
    const { error: profileError } = await adminClient
      .from("profiles")
      .delete()
      .eq("id", userId);

    if (profileError) {
      console.error("❌ delete-account: Failed to delete profile —", profileError.message);
    } else {
      console.log("✅ delete-account: Deleted profile");
    }

    // ── 4. Delete auth user (must be last) ──────────────────────────
    const { error: authDeleteError } = await adminClient.auth.admin.deleteUser(userId);

    if (authDeleteError) {
      console.error("❌ delete-account: Failed to delete auth user —", authDeleteError.message);
      return new Response(
        JSON.stringify({ success: false, message: `Failed to delete authentication record: ${authDeleteError.message}` }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    console.log(`✅ delete-account: Auth user ${userId} deleted successfully`);

    // ── 5. Return success ───────────────────────────────────────────
    return new Response(
      JSON.stringify({ success: true, message: "Account deleted successfully" }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("❌ delete-account: Unexpected error —", err);
    return new Response(
      JSON.stringify({ success: false, message: `An unexpected error occurred: ${err?.message ?? err}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
