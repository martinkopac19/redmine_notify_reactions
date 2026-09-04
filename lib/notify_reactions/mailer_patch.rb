# frozen_string_literal: true

module NotifyReactions
  # Mail o lajku. Zámerne krátky: príjemca potrebuje vedieť len kto, čo
  # a kde — obsah svojej vlastnej úlohy alebo komentára pozná.
  module MailerPatch
    extend ActiveSupport::Concern

    class_methods do
      # Príjemcu si vyberá volajúci (NotifyReactions.deliver), nie tento
      # mailer — kto smie mail dostať, sa rozhoduje na jednom mieste.
      def deliver_reaction_added(reaction, user)
        reaction_added(user, reaction).deliver_later
      end
    end

    def reaction_added(user, reaction)
      reactable = reaction.reactable
      project = reactable.project

      redmine_headers 'Project' => project&.identifier,
                      'Reaction-Type' => reactable.class.name

      # Vlákno mailu patrí lajknutej veci (u komentára jeho úlohe), nech
      # správa nesedí v schránke osamote. Vlastný Message-Id zámerne
      # nenastavujeme: Reaction nemá `created_on`, ktoré `token_for` v jadre
      # vyžaduje, a každý lajk má byť samostatná správa.
      root = nr_thread_root(reactable)
      references root if root

      @author = reaction.user
      @user = user
      @reaction = reaction
      @reactable = reactable
      @what = nr_what_label(reactable)
      @title = nr_title_for(reactable)
      @excerpt = nr_excerpt_for(reactable)
      @url = url_for(nr_url_options_for(reactable))

      subject = +''
      subject << "[#{project.name}] " if project
      subject << "👍 #{reaction.user.name}: #{@what}"

      mail :to => user, :subject => subject
    end

    private

    # Do ktorého mailového vlákna správa patrí.
    def nr_thread_root(reactable)
      case reactable
      when Journal then reactable.journalized
      when Comment then reactable.commented
      when Message then reactable.root
      else reactable
      end
    end

    # Comment (komentár k novinke) ako jediný z lajkovateľných typov nemá
    # `event_url` — kotva je z app/views/news/show.html.erb.
    def nr_url_options_for(reactable)
      if reactable.is_a?(Comment)
        { :controller => 'news', :action => 'show', :id => reactable.commented_id,
          :anchor => "message-#{reactable.id}" }
      else
        reactable.event_url
      end
    end

    def nr_what_label(reactable)
      case reactable
      when Issue then l(:nr_what_issue, :id => reactable.id)
      when Journal then l(:nr_what_journal, :id => reactable.journalized_id)
      when Message then l(:nr_what_message)
      when News then l(:nr_what_news)
      when Comment then l(:nr_what_comment)
      else reactable.class.name
      end
    end

    def nr_title_for(reactable)
      issue = reactable.is_a?(Journal) ? reactable.journalized : nil
      case reactable
      when Issue then "#{reactable.tracker.name} ##{reactable.id}: #{reactable.subject}"
      when Journal then "#{issue.tracker.name} ##{issue.id}: #{issue.subject}"
      when Message then reactable.subject
      when News then reactable.title
      when Comment then reactable.commented.title
      else reactable.to_s
      end
    end

    # Kúsok lajknutého textu, nech je jasné, o ktorý komentár ide.
    # Pri úlohe sa nevypisuje — jej názov je už v @title.
    def nr_excerpt_for(reactable)
      text = case reactable
             when Journal then reactable.notes
             when Message then reactable.content
             when Comment then reactable.content
             when News then reactable.description
             end
      return nil if text.blank?

      text.to_s.strip.truncate(300)
    end
  end
end
