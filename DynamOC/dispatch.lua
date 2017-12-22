local ffi = runtime.ffi
local dispatch = {}

ffi.cdef[[
// base.h
typedef union {
    struct dispatch_object_s *_do;
    struct dispatch_continuation_s *_dc;
    struct dispatch_queue_s *_dq;
    struct dispatch_queue_attr_s *_dqa;
    struct dispatch_group_s *_dg;
    struct dispatch_source_s *_ds;
    struct dispatch_source_attr_s *_dsa;
    struct dispatch_semaphore_s *_dsema;
    struct dispatch_data_s *_ddata;
    struct dispatch_io_s *_dchannel;
    struct dispatch_operation_s *_doperation;
    struct dispatch_disk_s *_ddisk;
} dispatch_object_t __attribute__((transparent_union));

// queue.h
typedef struct dispatch_queue_s *dispatch_queue_t;
typedef long dispatch_queue_priority_t;

struct dispatch_queue_s _dispatch_main_q;

dispatch_queue_t dispatch_get_global_queue(long identifier, unsigned long flags);
dispatch_queue_t dispatch_get_main_queue(void);

void dispatch_async(dispatch_queue_t queue, id block);
void dispatch_sync(dispatch_queue_t queue, id block);
]]

local lib = ffi.C --load("dispatch")


-- Types
dispatch.queue_priority_t                = ffi.typeof("dispatch_queue_priority_t")


-- Contants
dispatch.highPriority                    = ffi.cast(dispatch.queue_priority_t, 2)
dispatch.defaultPriority                 = ffi.cast(dispatch.queue_priority_t, 0)
dispatch.lowPriority                     = ffi.cast(dispatch.queue_priority_t, -2)
dispatch.backgroundPriority              = ffi.cast(dispatch.queue_priority_t, -32768) -- INT16_MIN

dispatch.mainQueue                       = lib._dispatch_main_q
dispatch.get_global_queue                = lib.dispatch_get_global_queue

-- Functions
function dispatch.async(queue, lambda)
    local block = runtime.createBlock(lambda, "@")
    block:setSyncDispatch_(false)
    block:retain()
    lib.dispatch_async(queue, block)
end

function dispatch.sync(queue, lambda)
    local block = runtime.createBlock(lambda, "@")
    block:setSyncDispatch_(true)
    lib.dispatch_sync(queue, block)
end

return dispatch
