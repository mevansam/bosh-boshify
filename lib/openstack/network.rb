class Network
    require 'ipaddr'
    require 'yaml'

    attr_reader :uuid
    attr_reader :subnet_uuid
    attr_reader :subnet_cidr

    attr_reader :gateway_ip

    def initialize(name, state_file)

        @state_file = state_file
        if File.exists?(@state_file)
            state = YAML.load_file(@state_file)
        end

        network = `neutron --insecure net-list 2> /dev/null | grep "#{name}"`.split(/[ \|]/).select { |v| !v.strip.empty? }
        raise "Error retrieving uuid of network '#{name}'." unless $?.success?

        @uuid = network[0]
        @subnet_uuid = network[2]
        @subnet_cidr = network[3]

        if state.nil? || (@uuid != state['uuid'] && @subnet_uuid != state['subnet_uuid'])

            subnet_detail = `neutron --insecure subnet-show #{@subnet_uuid} 2> /dev/null`.lines
            raise "Error retrieving subnet details" unless $?.success?

            @gateway_ip = subnet_detail.select { |l| l[/gateway_ip/,0] }.first[/(\d+\.\d+\.\d+\.\d+)/, 1]

            allocation_pool = subnet_detail.select { |l| l[/allocation_pools/,0] }.first
            
            ip = IPAddr.new(allocation_pool[/\"start\": \"(\d+\.\d+\.\d+\.\d+)\"/, 1])
            last = IPAddr.new(allocation_pool[/\"end\": \"(\d+\.\d+\.\d+\.\d+)\"/, 1]).succ

            allocated_ips = `neutron --insecure port-list 2> /dev/null | grep "#{subnet_uuid}"`.lines.each.map { |l| IPAddr.new(l[/\d+\.\d+\.\d+\.\d+/, 0]) }
            allocated_ips.select! { |i| (i<=>ip)>=0 }
            allocated_ips << last
            allocated_ips.sort!
            allocated_ips.reverse!

            @reserved = [ ]
            @ip_blocks = [ ]
            @ip_ranges = [ ]
            @static = { }

            begin
                ip_range = [ ]
                while (ip<=>allocated_ips.last)<0
                    ip_range << ip
                    ip = ip.succ
                end 
                @ip_ranges << ip_range if !ip_range.empty?
                ip = ip.succ
                reserved_ip = allocated_ips.pop
                if (reserved_ip<=>last)!=0
                    if @reserved.last && (@reserved.last.last.succ<=>reserved_ip)==0
                        @reserved.last << reserved_ip
                    else
                        @reserved << [ reserved_ip ]
                    end
                end
            end while !allocated_ips.empty?

            @loaded_saved_state = false
        else
            STDERR.print("Reading saved network state from #{@state_file}.\n")

            @gateway_ip = state['gateway_ip']
            @reserved = state['reserved'].map { |b| b.map { |i| IPAddr.new(i) } }
            @ip_blocks = state['ip_blocks'].map { |b| b.map { |i| IPAddr.new(i) } }
            @ip_ranges = state['ip_ranges'].map { |b| b.map { |i| IPAddr.new(i) } }
            @static = { }

            @loaded_saved_state = true
        end
    end

    def allocate_block(num_ips)
        if @loaded_saved_state
            @ip_blocks.size.times do |i|
                return i if @ip_blocks[i].size==num_ips
            end
        else
            @ip_ranges.each do |r|
                if num_ips<=r.size
                    @ip_blocks << r.slice!(0, num_ips)
                    @ip_ranges.delete(r) if r.empty?
                    return @ip_blocks.size-1
                end
            end
            raise "Unable to find a contiguous block of #{num_ips} IPs."
        end
    end

    def get_reserved_ranges()
        reserved = [ ]
        @reserved.each do |r|
            reserved << "#{r.first} - #{r.last}"
        end
        @ip_ranges.each do |r|
            reserved << "#{r.first} - #{r.last}"
        end
        reserved
    end

    def get_static_ranges()
        static = [ ]
        @static.keys.each do |b|
            static << "#{@ip_blocks[b].first}-#{@ip_blocks[b].last}"
        end
        static
    end

    def get_static_ip(block)
        i = @static[block] || 0
        @static[block] = i+1
        @ip_blocks[block][i]
    end

    def save

        state = { }
        state['uuid'] = @uuid
        state['subnet_uuid'] = @subnet_uuid
        state['subnet_cidr'] = @subnet_cidr
        state['gateway_ip'] = @gateway_ip
        state['reserved'] = @reserved.map { |b| b.map { |i| i.to_s } }
        state['ip_blocks'] = @ip_blocks.map { |b| b.map { |i| i.to_s } }
        state['ip_ranges'] = @ip_ranges.map { |b| b.map { |i| i.to_s } }

        File.open(@state_file, 'w+') { |f| f.write(state.to_yaml) }
    end
end
