class State < Hash

    def load(state_file)
        @state_file = state_file
        if File.exists?(@state_file)
            state = YAML.load_file(@state_file)
            state.each { |k,v| self[k] = v }
            return true
        end
        return false
    end

    def save
        state = Hash.new
        self.each { |k,v| state[k] = v }
        File.open(@state_file, 'w+') { |f| f.write(state.to_yaml) }
    end
end