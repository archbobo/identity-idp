require 'rails_helper'

RSpec.describe LambdaJobs::Runner do
  subject(:runner) do
    LambdaJobs::Runner.new(job_name: job_name, args: args, job_class: job_class)
  end

  let(:job_name) { 'my-job' }
  let(:args) { { foo: 'bar' } }
  let(:job_class) { double('JobClass') }
  let(:aws_lambda_proofing_enabled) { 'true' }

  let(:git_ref) { '1234567890abcdefghijklmnop' }
  before do
    stub_const('LambdaJobs::GIT_REF', git_ref)
  end

  describe '#function_name' do
    it 'adds the first 10 characters of the GIT_REF' do
      expect(runner.function_name).to eq('my-job:1234567890')
    end
  end

  describe '#run' do
    before do
      allow(LoginGov::Hostdata).to receive(:in_datacenter?).and_return(in_datacenter)
      allow(Figaro.env).to receive(:aws_lambda_proofing_enabled).
        and_return(aws_lambda_proofing_enabled)
    end

    context 'when run in a deployed environment' do
      let(:in_datacenter) { true }

      context 'when aws_lambda_proofing_enabled is true' do
        let(:aws_lambda_proofing_enabled) { 'true' }

        let(:aws_lambda_client) { instance_double(Aws::Lambda::Client) }
        before do
          expect(runner).to receive(:aws_lambda_client).and_return(aws_lambda_client)
        end

        it 'involves a lambda in AWS' do
          expect(aws_lambda_client).to receive(:invoke).with(
            function_name: 'my-job:1234567890',
            invocation_type: 'Event',
            log_type: 'None',
            payload: args.to_json,
          )

          runner.run
        end
      end

      context 'when aws_lambda_proofing_enabled is false' do
        let(:aws_lambda_proofing_enabled) { 'false' }

        it 'calls JobClass.handle' do
          expect(job_class).to receive(:handle).with(
            event: { 'body' => args.to_json },
            context: nil,
          )

          runner.run
        end
      end
    end

    context 'when run locally' do
      let(:in_datacenter) { false }

      it 'calls JobClass.handle' do
        expect(job_class).to receive(:handle).with(
          event: { 'body' => args.to_json },
          context: nil,
        )

        runner.run
      end

      context 'when run locally with a block' do
        it 'passes the block to the handler' do
          result = Object.new

          expect(job_class).to receive(:handle).with(
            event: { 'body' => args.to_json },
            context: nil,
          ).and_yield(result)

          yielded_result = nil
          runner.run do |callback_result|
            yielded_result = callback_result
          end

          expect(yielded_result).to eq(result)
        end
      end
    end
  end
end
