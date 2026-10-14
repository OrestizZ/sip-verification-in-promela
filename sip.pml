/* Messages for SIP and ABP */
mtype = { INVITE, TRYING, RINGING, OK, ACK, BYE, ABP_ACK,
          BUSY, REJECTED, NOT_FOUND,
          ID_ALICE, ID_PROXY, ID_BOB};

#define INNER_CHANNEL_SIZE 0
#define NETWORK_CHANNEL_SIZE 3
#define MAX_NETWORK_DROPS 3

/* --- INTERNAL CHANNELS (Rendezvous) --- */
/* Communication between application and local transport layer (TCP/ABP) */
chan alice_to_trA = [INNER_CHANNEL_SIZE] of { mtype, mtype }; /* dest_id, msg */
chan proxy_to_trP = [INNER_CHANNEL_SIZE] of { mtype, mtype }; /* dest_id, msg */
chan rP_to_proxy  = [INNER_CHANNEL_SIZE] of { mtype }; /* msg */
chan rB_to_bob    = [INNER_CHANNEL_SIZE] of { mtype }; /* msg */

/* --- NETWORK CHANNELS --- */

/* Direction to Bob using ABP */
chan trA_to_net = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, mtype, bit }; /* src_id, dest_id, msg, seq */
chan trP_to_net = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, mtype, bit }; /* src_id, dest_id, msg, seq */

chan net_to_rP = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, mtype, bit }; /* src_id, dest_id, msg, seq */
chan net_to_rB = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, mtype, bit }; /* src_id, dest_id, msg, seq */

/* Response channels for ABP acknowledgments */
chan rP_to_net_ack  = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, bit }; /* dest_id, msg, seq */
chan rB_to_net_ack  = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, bit }; /* dest_id, msg, seq */

chan net_to_trA_ack = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, bit }; /* dest_id, msg, seq */
chan net_to_trP_ack = [NETWORK_CHANNEL_SIZE] of { mtype, mtype, bit }; /* dest_id, msg, seq */

/* Direction from Bob and Proxy to the network without ABP */
chan proxy_to_net = [NETWORK_CHANNEL_SIZE] of { mtype, mtype }; /* dest_id, msg */
chan bob_to_net   = [NETWORK_CHANNEL_SIZE] of { mtype, mtype }; /* dest_id, msg */

chan net_to_alice = [NETWORK_CHANNEL_SIZE] of { mtype }; /* msg */
chan net_to_proxy = [NETWORK_CHANNEL_SIZE] of { mtype }; /* msg */

/* ==================================== ALICE ==================================== */

proctype Alice() {
    /* Track the state of the call for verification purposes */
    bool call_is_active = false;

    /* Begin the call: Send INVITE to the Proxy */
    alice_to_trA ! ID_PROXY, INVITE;

    /* Wait for Trying from the network */
    net_to_alice ? TRYING;

    /* Handle the response from the network */
    if
    /* Happy Path */
    :: net_to_alice ? RINGING ->
        net_to_alice ? OK;
        alice_to_trA ! ID_BOB, ACK;
        call_is_active = true;
        
        /* Call is ongoing */
        
        /* End of call */
        assert(call_is_active == true);
        alice_to_trA ! ID_BOB, BYE;
        net_to_alice ? OK;
        /* The process terminates here */

progress_alice_success: 
        skip;

    /* Error Cases */
    :: net_to_alice ? NOT_FOUND ->
        assert(call_is_active == false);
        alice_to_trA ! ID_PROXY, ACK;
        /* The process terminates here */

progress_alice_notfound: 
        skip;
        
    :: net_to_alice ? BUSY ->
        assert(call_is_active == false);
        alice_to_trA ! ID_PROXY, ACK;
        /* The process terminates here */

progress_alice_busy: 
        skip;
    :: net_to_alice ? REJECTED ->
        assert(call_is_active == false);
        alice_to_trA ! ID_PROXY, ACK;
        /* The process terminates here */

progress_alice_rejected: 
        skip;
    fi
}

proctype Alice_ABP_Transmitter() {
    mtype dest, msg;
    
    /* Sequence bits for each destination */
    bit seq_proxy = 0;
    bit seq_bob = 0;
    
    /* Temporary variable for the current bit */
    bit current_seq;
    
    mtype ack_dest, ack_msg;
    bit ack_seq;

end_alice_abp_transmitter:
    do
    /* Wait for destination and message from Alice */
    :: alice_to_trA ? dest, msg -> 
        
        /* Select the correct bit according to the recipient */
        if
        :: (dest == ID_PROXY) -> current_seq = seq_proxy
        :: (dest == ID_BOB)   -> current_seq = seq_bob
        fi;

        /* Send to the network with the correct current_seq */
        trA_to_net ! ID_ALICE, dest, msg, current_seq;

        /* Wait for acknowledgment (ABP_ACK) or Timeout */
        do
        :: net_to_trA_ack ? ack_dest, ack_msg, ack_seq ->
            if
            /* ACK is the expected one */
            :: (ack_msg == ABP_ACK && ack_seq == current_seq) -> 
                
                /* Update the correct bit for the next packet */
                if
                :: (dest == ID_PROXY) -> seq_proxy = 1 - seq_proxy
                :: (dest == ID_BOB)   -> seq_bob = 1 - seq_bob
                fi;
                
                break /* Exit the wait loop */
                
            /* ACK is not the expected one, ignore */
            :: else -> 
                skip
            fi
            
        /* If the packet is lost (Timeout) */
        :: timeout ->
            /* Resend the packet */
            trA_to_net ! ID_ALICE, dest, msg, current_seq
        od
    od
}

/* ==================================== PROXY ==================================== */

proctype Proxy() {
    /* Receive INVITE from Alice */
    rP_to_proxy ? INVITE;

    /* Immediate response Trying to Alice */
    proxy_to_net ! ID_ALICE, TRYING;

    /* Non-deterministic choice, Bob Found or Not Found */
    if
    /* Bob is found -> Forward the INVITE */
    :: proxy_to_trP ! ID_BOB, INVITE ->
        
        /* We wait to see what Bob will respond with */
        if
        /* Happy Path */
        :: net_to_proxy ? RINGING ->
            proxy_to_net ! ID_ALICE, RINGING;
            net_to_proxy ? OK;
            proxy_to_net ! ID_ALICE, OK;
            /* Process terminates here */
progress_proxy_success: 
            skip;

        /* Bob is busy */
        :: net_to_proxy ? BUSY ->
            proxy_to_net ! ID_ALICE, BUSY;
            
            /* Wait for the acknowledgment ACK from Alice */
            rP_to_proxy ? ACK;
            /* Process terminates here */
progress_proxy_busy: 
            skip;

        /* Bob rejected the call */
        :: net_to_proxy ? REJECTED ->
            proxy_to_net ! ID_ALICE, REJECTED;
            
            /* Wait for the acknowledgment ACK from Alice */
            rP_to_proxy ? ACK;
            /* Process terminates here */
progress_proxy_rejected: 
            skip;
        fi

    /* Bob is not found */
    :: proxy_to_net ! ID_ALICE, NOT_FOUND ->
        
        /* Wait for the acknowledgment ACK from Alice */
        rP_to_proxy ? ACK;
        /* Process terminates here */
progress_proxy_notfound: 
        skip;
    fi
}

proctype Proxy_ABP_Transmitter() {
    mtype dest, msg;
    bit seq = 0;

    mtype ack_dest, ack_msg;
    bit ack_seq;

end_proxy_abp_transmitter:
    do
    /* Receive from Proxy */
    :: proxy_to_trP ? dest, msg -> 
        
        /* Initial transmission to the network */
        trP_to_net ! ID_PROXY, dest, msg, seq;

        /* Wait for acknowledgment (ABP_ACK) or Timeout */
        do
        :: net_to_trP_ack ? ack_dest, ack_msg, ack_seq ->
            if
            :: (ack_msg == ABP_ACK && ack_seq == seq) -> 
                seq = 1 - seq;
                break
            :: else -> 
                skip
            fi
            
        :: timeout ->
            /* The packet or ACK was lost: Resend */
            trP_to_net ! ID_PROXY, dest, msg, seq
        od
    od
}

proctype Proxy_ABP_Receiver() {
    mtype src, dest, msg;
    bit seq;
    bit expected_seq = 0; /* Add the "memory" of the receiver */

end_proxy_abp_receiver:
    do
    /* Receive packet from the network */
    :: net_to_rP ? src, dest, msg, seq ->
        if
        /* New Message */
        :: (seq == expected_seq) ->
            /* Forward to the application */
            rP_to_proxy ! msg;
            /* Send ACK */
            rP_to_net_ack ! src, ABP_ACK, seq;
            /* Change the bit we are waiting for */
            expected_seq = 1 - expected_seq
            
        /* Duplicate Message (The previous ACK was lost) */
        :: (seq != expected_seq) ->
            /* We ignore the message for the application, just resend the ACK */
            rP_to_net_ack ! src, ABP_ACK, seq
        fi
    od
}

/* ==================================== BOB ==================================== */

proctype Bob() {
end_bob:

    /* Receive INVITE from the Proxy */
    rB_to_bob ? INVITE;

    /* Random choice of Bob's response */
    if
    /* Accept the call (Happy Path) */
    :: bob_to_net ! ID_PROXY, RINGING ->
        bob_to_net ! ID_PROXY, OK;
        
        /* Receive ACK from Alice */
        rB_to_bob ? ACK;
        
        /* The call is active */
        
        /* Receive BYE from Alice */
        rB_to_bob ? BYE;
        
        /* Termination: Send final 200 OK to Alice */
        bob_to_net ! ID_ALICE, OK;
        /* Process terminates here */
progress_bob_success: 
        skip;

    /* Bob is busy */
    :: bob_to_net ! ID_PROXY, BUSY ->
        /* Process terminates here */
progress_bob_busy: 
        skip;

    /* Bob rejects the call */
    :: bob_to_net ! ID_PROXY, REJECTED ->
        /* Process terminates here */
progress_bob_rejected:
        skip;
    fi
}

proctype Bob_ABP_Receiver() {
    mtype src, dest, msg;
    bit seq;
    
    /* Sequence bits for each sender */
    bit exp_seq_alice = 0;
    bit exp_seq_proxy = 0;
    
    /* Temporary variable for the check */
    bit current_exp;

end_bob_abp_receiver:
    do
    :: net_to_rB ? src, dest, msg, seq ->
        
        /* We find which sequence bit we are waiting for from this sender */
        if
        :: (src == ID_ALICE) -> current_exp = exp_seq_alice
        :: (src == ID_PROXY) -> current_exp = exp_seq_proxy
        fi;

        /* We check if the packet is new or a duplicate */
        if
        /* New Message */
        :: (seq == current_exp) ->
            /* Forward to the application */
            rB_to_bob ! msg;
            
            /* Send ACK */
            rB_to_net_ack ! src, ABP_ACK, seq;
            
            /* Update the expected sequence bit according to the sender */
            if
            :: (src == ID_ALICE) -> exp_seq_alice = 1 - exp_seq_alice
            :: (src == ID_PROXY) -> exp_seq_proxy = 1 - exp_seq_proxy
            fi
            
        /* Duplicate Message (The previous ACK was lost) */
        :: (seq != current_exp) ->
            /* We ignore the message for the application and resend the ACK */
            rB_to_net_ack ! src, ABP_ACK, seq
        fi
    od
}

/* ==================================== NETWORK ==================================== */

proctype Network() {
    mtype src, dest, msg;
    bit seq;
    
    /* Counter for total drops in the simulation for verification purposes */
    byte total_drops = 0;

end_network:
    do
    /* ABP Packets */
    :: trA_to_net ? src, dest, msg, seq ->
        if
        :: (dest == ID_PROXY) -> net_to_rP ! src, dest, msg, seq
        :: (dest == ID_BOB)   -> net_to_rB ! src, dest, msg, seq
        :: (total_drops < MAX_NETWORK_DROPS)  -> total_drops++; skip
        fi

    :: trP_to_net ? src, dest, msg, seq ->
        if
        :: (dest == ID_BOB)   -> net_to_rB ! src, dest, msg, seq
        :: (total_drops < MAX_NETWORK_DROPS)  -> total_drops++; skip
        fi

    /* ABP_ACK Packets */
    :: rP_to_net_ack ? dest, msg, seq ->
        if
        :: (dest == ID_ALICE) -> net_to_trA_ack ! dest, msg, seq
        :: (total_drops < MAX_NETWORK_DROPS)  -> total_drops++; skip
        fi

    :: rB_to_net_ack ? dest, msg, seq ->
        if
        :: (dest == ID_ALICE) -> net_to_trA_ack ! dest, msg, seq
        :: (dest == ID_PROXY) -> net_to_trP_ack ! dest, msg, seq
        :: (total_drops < MAX_NETWORK_DROPS)  -> total_drops++; skip
        fi

    /* Application Messages (SIP) */
    :: proxy_to_net ? dest, msg ->
        if
        :: (dest == ID_ALICE) -> net_to_alice ! msg
        fi

    :: bob_to_net ? dest, msg ->
        if
        :: (dest == ID_PROXY) -> net_to_proxy ! msg
        :: (dest == ID_ALICE) -> net_to_alice ! msg
        fi
    od
}

/* ==================================== INIT ==================================== */

init {
    atomic {
        run Alice();
        run Proxy();
        run Bob();

        run Alice_ABP_Transmitter();

        run Proxy_ABP_Receiver();
        run Proxy_ABP_Transmitter();

        run Bob_ABP_Receiver();

        run Network();
    }
}