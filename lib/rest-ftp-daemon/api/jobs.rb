module RestFtpDaemon
  module API

    class Jobs < Grape::API
      include RestFtpDaemon::API::Defaults
      logger ActiveSupport::Logger.new APP_LOGTO, 'daily'

      params do
        # requires :id, type: Integer
        #requires :id, type: Integer, desc: "job id"
        optional :overwrite, type: Integer, default: false
        # requires :status, type: Symbol, values: [:not_started, :processing, :done]
        # optional :text, type: String, regexp: /^[a-z]+$/
        # group :media do
        #   requires :url
        # end
        # optional :audio do
        #   requires :format, type: Symbol, values: [:mp3, :wav, :aac, :ogg], default: :mp3
        # end
        # mutually_exclusive :media, :audio
      end

      helpers do
        def info message, level = 0
          Jobs.logger.add(Logger::INFO, "#{'  '*level} #{message}", "API::Jobs")
        end

        def threads_with_id job_id
          $threads.list.select do |thread|
            next unless thread[:job].is_a? Job
            thread[:job].id == job_id
          end
        end

        def job_describe job_id
          # Find threads with tihs id
          threads = threads_with_id job_id
          raise RestFtpDaemon::JobNotFound if threads.empty?

          # Find first job with tihs id
          job = threads.first[:job]
          raise RestFtpDaemon::JobNotFound unless job.is_a? Job
          description = job.describe

          # Return job description
          description
        end

        def job_delete job_id
          # Find threads with tihs id
          threads = threads_with_id job_id
          raise RestFtpDaemon::JobNotFound if threads.empty?

          # Get description just before terminating the job
          job = threads.first[:job]
          raise RestFtpDaemon::JobNotFound unless job.is_a? Job
          description = job.describe

          # Kill those threads
          threads.each do |t|
            Thread.kill(t)
          end

          # Return job description
          description
        end

        def job_list
          $threads.list.map do |thread|
            next unless thread[:job].is_a? Job
            thread[:job].describe
          end
        end

      end

      # def initialize
      #   # Setup logger
      #   #@@logger = Logger.new(APP_LOGTO, 'daily')
      #   # @@queue = Queue.new

      #   # Create new thread group
      #   $threads = ThreadGroup.new

      #   # Other stuff
      #   $last_worker_id = 0
      #   #info "initialized"
      #   super
      # end

      # Get job info
      # params do
      #   requires :id, type: Integer, desc: "job id"
      # end


      desc "Get information about a specific job"
      params do
        requires :id, type: Integer, desc: "job id"
      end
      get ':id' do
        info "GET /jobs/#{params[:id]}"
        begin
          response = job_describe params[:id].to_i
        rescue RestFtpDaemon::JobNotFound => exception
          status 404
          api_error exception
        rescue RestFtpDaemonException => exception
          status 500
          api_error exception
        rescue Exception => exception
          status 501
          api_error exception
        else
          status 200
          response
        end
      end

      # Delete jobs
      desc "Kill and remove a specific job"
      delete ':id' do
       info "DELETE /jobs/#{params[:name]}"
        begin
          response = job_delete params[:id].to_i
        rescue RestFtpDaemon::JobNotFound => exception
          status 404
          api_error exception
        rescue RestFtpDaemonException => exception
          status 500
          api_error exception
        rescue Exception => exception
          status 501
          api_error exception
        else
          status 200
          response
        end
      end

      # List jobs
      desc "Get a list of jobs"
      get do
        info "GET /jobs"
        begin
          response = job_list
        rescue RestFtpDaemonException => exception
          status 501
          api_error exception
        rescue Exception => exception
          status 501
          api_error exception
        else
          status 200
          response
        end
      end


      # Spawn a new thread for this new job
      desc "Create a new job"
      post do
        info "POST /jobs: #{request.body.read}"
        begin
          # Extract params
          request.body.rewind
          params = JSON.parse request.body.read

          # Create a new job
          job_id = $last_worker_id += 1
          job = Job.new(job_id, params)

          # Put it inside a thread
          th = Thread.new(job, job_id) do |thread|
            # Tnitialize thread
            Thread.abort_on_exception = true
            Thread.current[:job] = job
            info "[job #{job_id}] thread created ", 1

            # Do the job
            job.process

            # Wait for a few seconds before cleaning up the job
            info "[job #{job_id}] thread wandering for #{RestFtpDaemon::THREAD_SLEEP_BEFORE_DIE} seconds", 1
            job.wander RestFtpDaemon::THREAD_SLEEP_BEFORE_DIE
            info "[job #{job_id}] thread ending", 1
          end

          # Stack it to the pool
          #@@queue << job
          $threads.add th

          # And start it asynchronously
          #job.future.process

        rescue JSON::ParserError => exception
          status 406
          api_error exception
        rescue RestFtpDaemonException => exception
          status 412
          api_error exception
        rescue Exception => exception
          status 501
          api_error exception
        else
          status 201
          job.describe
        end
      end

    end
  end
end
